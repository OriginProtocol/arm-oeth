const { ethers, formatUnits, parseUnits } = require("ethers");
const dayjs = require("dayjs");
const utc = require("dayjs/plugin/utc");

const { claimableRequests } = require("../utils/armQueue");
const {
  adapterContract,
  claimBaseAssetWithdrawal,
  getOutstandingWithdrawals,
  requestBaseAssetWithdrawal,
  resolveArmBase,
} = require("../utils/arm");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:liquidity");

// Extend Day.js with the UTC plugin
dayjs.extend(utc);

const autoRequestWithdraw = async (options) => {
  const { amount, signer } = options;
  const baseContext = await resolveArmBase(options);
  const { baseSymbol } = baseContext;

  const withdrawAmount = amount
    ? parseUnits(amount.toString())
    : await baseWithdrawAmount(options);
  if (!withdrawAmount || withdrawAmount === 0n) return;

  log(
    `About to request withdrawal of ${formatUnits(withdrawAmount)} ${baseSymbol}`,
  );

  const tx = await requestBaseAssetWithdrawal({
    baseContext,
    signer,
    amount: withdrawAmount,
  });
  await logTxDetails(tx, "requestRedeem");
};

const autoClaimWithdraw = async ({
  signer,
  liquidityAsset,
  arm,
  armName,
  base,
  vault,
  confirm,
  id,
}) => {
  const baseContext = await resolveArmBase({ arm, armName, base });
  const { config } = baseContext;
  const adapter =
    baseContext.version === "legacy"
      ? undefined
      : await adapterContract(config.adapter, signer);
  const liquiditySymbol = await liquidityAsset.symbol();
  // Get amount of requests that have already been claimed
  const { claimed } = await vault.withdrawalQueueMetadata();

  // Get liquidity balance in the Vault
  const vaultLiquidity = await liquidityAsset.balanceOf(
    await vault.getAddress(),
  );

  const queuedAmountClaimable = claimed + vaultLiquidity;
  log(
    `Claimable queued amount is ${formatUnits(claimed)} claimed + ${formatUnits(
      vaultLiquidity,
    )} ${liquiditySymbol} in vault = ${formatUnits(queuedAmountClaimable)}`,
  );

  // Get the Date time of 10 minutes ago
  const now = dayjs();
  const claimDelaySeconds = await vault.withdrawalClaimDelay();
  const claimCutoff = now.subtract(Number(claimDelaySeconds), "seconds");
  log(
    `${claimDelaySeconds} second claim delay gives claim cutoff timestamp: ${claimCutoff.unix()} ${claimCutoff.toISOString()}`,
  );

  // get claimable withdrawal requests
  let requestIds = id
    ? [id]
    : await claimableRequests({
        withdrawer:
          baseContext.version === "legacy"
            ? await arm.getAddress()
            : config.adapter,
        queuedAmountClaimable,
        claimCutoff,
      });

  if (requestIds.length === 0) {
    log("No claimable requests");
    return requestIds;
  }

  log(`About to claim requests: ${requestIds} `);

  let shares = 0n;
  if (baseContext.version !== "legacy") {
    for (const requestId of requestIds) {
      shares += await adapter["requestShares(uint256)"](requestId);
    }
    if (shares === 0n) {
      log(
        `Withdrawal request${requestIds.length === 1 ? "" : "s"} ${requestIds} does not belong to the ${baseContext.baseSymbol} adapter`,
      );
      return [];
    }
  }

  const tx = await claimBaseAssetWithdrawal({
    baseContext,
    signer,
    shares,
    requestIds,
  });
  await logTxDetails(tx, "claimRedeem", confirm);

  return requestIds;
};

const baseWithdrawAmount = async (options) => {
  const {
    signer,
    arm,
    thresholdAmount,
    minAmount = "0.03",
    // Base asset decimals. eg 18 for sUSDe, 6 for PYUSD.
    decimals = 18,
    // Liquidity asset decimals, which can differ from the base asset ones,
    // eg an 18 decimals base asset over a 6 decimals USDC liquidity asset.
    liquidityDecimals = decimals,
  } = options;
  const { baseAddress, baseSymbol } = await resolveArmBase(options);

  // Withdrawal amount is base assets in ARM if not specified
  const baseAsset = new ethers.Contract(
    baseAddress,
    ["function balanceOf(address) external view returns (uint256)"],
    signer,
  );
  const withdrawAmount = await baseAsset.balanceOf(await arm.getAddress());
  log(`${formatUnits(withdrawAmount, decimals)} ${baseSymbol} withdraw amount`);

  // Exit if less than the minimum withdrawal amount
  const minAmountBI = parseUnits(minAmount.toString(), decimals);
  if (withdrawAmount <= minAmountBI) {
    console.log(`Not enough base assets left in the ARM to withdraw`);
    return 0n;
  }

  const thresholdAmountBI = parseUnits(thresholdAmount.toString(), decimals);

  // If above minimum threshold, return the withdraw amount
  if (withdrawAmount > thresholdAmountBI) {
    return withdrawAmount;
  }

  // If below minimum threshold, check if there is liquidity available in the ARM or lending market and skip if so

  // Get the amount of liquidity available in the ARM
  const liquidAsset = new ethers.Contract(
    await arm.liquidityAsset(),
    ["function balanceOf(address) external view returns (uint256)"],
    signer,
  );
  let liquidAssetAmount = await liquidAsset.balanceOf(await arm.getAddress());
  log(
    `${formatUnits(liquidAssetAmount, liquidityDecimals)} liquid asset balance in ARM`,
  );

  const outstanding = await getOutstandingWithdrawals(arm);
  log(
    `${formatUnits(outstanding, liquidityDecimals)} outstanding withdrawal requests`,
  );
  let liquidityAvailable = liquidAssetAmount - outstanding;
  log(
    `${formatUnits(liquidityAvailable, liquidityDecimals)} liquidity available in ARM after accounting for outstanding withdrawal requests`,
  );

  // Get the amount of liquidity available in the active market if one exists
  const activeMarketAddress = await arm.activeMarket();
  if (activeMarketAddress !== ethers.ZeroAddress) {
    const activeMarket = new ethers.Contract(
      activeMarketAddress,
      ["function maxWithdraw(address) external view returns (uint256)"],
      signer,
    );
    const lendingMarketLiquidityAmount = await activeMarket.maxWithdraw(
      await arm.getAddress(),
    );
    log(
      `${formatUnits(lendingMarketLiquidityAmount, liquidityDecimals)} liquidity available in lending market`,
    );

    // Add liquidity in ARM and lending market together to determine if we can skip the withdrawal
    liquidityAvailable += lendingMarketLiquidityAmount;
  }

  // If liquidity available is above the minimum amount, skip withdrawal.
  // minAmount is re-parsed at liquidity decimals as the assets are pegged
  // ~1:1 but can have different decimals.
  const minLiquidityBI = parseUnits(minAmount.toString(), liquidityDecimals);
  if (liquidityAvailable > minLiquidityBI) {
    console.log(
      `withdraw amount of ${formatUnits(
        withdrawAmount,
        decimals,
      )} is below ${thresholdAmount} threshold and ${formatUnits(liquidityAvailable, liquidityDecimals)} liquidity is still available, so not withdrawing`,
    );
    return 0n;
  }

  log(
    `Only ${formatUnits(liquidityAvailable, liquidityDecimals)} liquidity available, withdrawing ${formatUnits(withdrawAmount, decimals)} despite being below minimum threshold of ${thresholdAmount}`,
  );

  return withdrawAmount;
};

module.exports = {
  autoRequestWithdraw,
  autoClaimWithdraw,
  baseWithdrawAmount,
};
