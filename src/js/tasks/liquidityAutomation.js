const { formatUnits, parseUnits } = require("ethers");
const dayjs = require("dayjs");
const utc = require("dayjs/plugin/utc");

const { claimableRequests } = require("../utils/armQueue");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:liquidity");

// Extend Day.js with the UTC plugin
dayjs.extend(utc);

const autoRequestWithdraw = async ({
  signer,
  baseAsset,
  arm,
  minAmount,
  confirm,
}) => {
  const symbol = await baseAsset.symbol();
  const assetBalance = await baseAsset.balanceOf(await arm.getAddress());
  log(`${formatUnits(assetBalance)} ${symbol} in ARM`);

  const minAmountBI = parseUnits(minAmount.toString(), 18);

  if (assetBalance <= minAmountBI) {
    console.log(
      `${formatUnits(
        assetBalance,
      )} ${symbol} is below ${minAmount} so not withdrawing`,
    );
    return;
  }

  log(`About to request ${formatUnits(assetBalance)} ${symbol} withdrawal`);

  const tx = await arm.connect(signer).requestOriginWithdrawal(assetBalance);
  await logTxDetails(tx, "requestOriginWithdrawal", confirm);
};

const autoClaimWithdraw = async ({
  signer,
  liquidityAsset,
  arm,
  vault,
  confirm,
}) => {
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
  let requestIds = await claimableRequests({
    withdrawer: await arm.getAddress(),
    queuedAmountClaimable,
    claimCutoff,
  });

  if (requestIds.length === 0) {
    log("No claimable requests");
    return requestIds;
  }

  log(`About to claim requests: ${requestIds} `);

  const tx = await arm.connect(signer).claimOriginWithdrawals(requestIds);
  await logTxDetails(tx, "claimOriginWithdrawals", confirm);

  return requestIds;
};

const baseWithdrawAmount = async (options) => {
  const { signer, arm, thresholdAmount, minAmount = "0.03" } = options;

  // Withdrawal amount is base assets in ARM if not specified
  const baseAsset = new ethers.Contract(
    await arm.baseAsset(),
    ["function balanceOf(address) external view returns (uint256)"],
    signer,
  );
  const withdrawAmount = await baseAsset.balanceOf(arm.getAddress());
  log(`${formatUnits(withdrawAmount)} withdraw amount`);

  // Exit if less than the minimum withdrawal amount
  const minAmountBI = parseUnits(minAmount.toString(), 18);
  if (withdrawAmount <= minAmountBI) {
    console.log(`Not enough base assets left in the ARM to withdraw`);
    return 0n;
  }

  const thresholdAmountBI = parseUnits(thresholdAmount.toString());

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
  log(`${formatUnits(liquidAssetAmount)} liquid asset balance in ARM`);

  const queue = await arm.withdrawsQueued();
  const claimed = await arm.withdrawsClaimed();
  const outstanding = queue - claimed;
  log(`${formatUnits(outstanding)} outstanding withdrawal requests`);
  let liquidityAvailable = liquidAssetAmount - outstanding;
  log(
    `${formatUnits(liquidityAvailable)} liquidity available in ARM after accounting for outstanding withdrawal requests`,
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
      `${formatUnits(lendingMarketLiquidityAmount)} liquidity available in lending market`,
    );

    // Add liquidity in ARM and lending market together to determine if we can skip the withdrawal
    liquidityAvailable += lendingMarketLiquidityAmount;
  }

  // If liquidity available is above the minimum amount, skip withdrawal
  if (liquidityAvailable > minAmountBI) {
    console.log(
      `withdraw amount of ${formatUnits(
        withdrawAmount,
      )} is below ${thresholdAmount} threshold and ${formatUnits(liquidityAvailable)} liquidity is still available, so not withdrawing`,
    );
    return 0n;
  }

  log(
    `Only ${formatUnits(liquidityAvailable)} liquidity available, withdrawing ${formatUnits(withdrawAmount)} despite being below minimum threshold of ${thresholdAmount}`,
  );

  return withdrawAmount;
};

module.exports = {
  autoRequestWithdraw,
  autoClaimWithdraw,
  baseWithdrawAmount,
};
