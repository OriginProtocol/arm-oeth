const { formatUnits, parseUnits } = require("ethers");
const dayjs = require("dayjs");
const utc = require("dayjs/plugin/utc");

const { getBlock } = require("../utils/block");
const { resolveArmContract } = require("../utils/addressParser");
const { logWithdrawalRequests } = require("../utils/etherFi");
const {
  logArmPrices,
  log1InchPrices,
  logKyberPrices,
  logWrappedEtherFiPrices,
} = require("./markets");
const { getMerklRewards } = require("../utils/merkl");
const { convertToAsset } = require("../utils/pricing");
const { logTxDetails } = require("../utils/txLogger");
const { getSigner } = require("../utils/signers");
const {
  adapterContract,
  claimBaseAssetWithdrawal,
  getArmBaseSymbols,
  getArmBuffer,
  getOutstandingWithdrawals,
  normalizeArmName,
  requestBaseAssetWithdrawal,
  resolveArmBase,
} = require("../utils/arm");

const log = require("../utils/logger")("task:liquidity");

// Extend Day.js with the UTC plugin
dayjs.extend(utc);

const scaleDecimals = (value, fromDecimals, toDecimals) => {
  if (fromDecimals === toDecimals) return value;
  if (fromDecimals > toDecimals) {
    return value / 10n ** BigInt(fromDecimals - toDecimals);
  }
  return value * 10n ** BigInt(toDecimals - fromDecimals);
};

const requestWithdraw = async ({ amount, signer, arm, armName, base }) => {
  const amountBI = parseUnits(amount.toString(), 18);
  const baseContext = await resolveArmBase({
    arm,
    armName,
    base,
  });
  const { baseSymbol } = baseContext;

  log(`About to request ${amount} ${baseSymbol} withdrawal`);

  const tx = await requestBaseAssetWithdrawal({
    baseContext,
    signer,
    amount: amountBI,
  });

  await logTxDetails(tx, "requestRedeem");

  // TODO parse the request id from the WithdrawalRequested event on the OETH Vault
};

const claimWithdraw = async ({ id, signer, arm, armName, base }) => {
  const baseContext = await resolveArmBase({
    arm,
    armName,
    base,
  });
  let shares = 0n;
  if (baseContext.version !== "legacy") {
    const adapter = await adapterContract(baseContext.config.adapter, signer);
    shares = await adapter["requestShares(uint256)"](id);
  }
  const tx = await claimBaseAssetWithdrawal({
    baseContext,
    signer,
    shares,
    requestIds: [id],
  });

  log(`About to claim withdrawal request ${id}`);
  await logTxDetails(tx, "claimRedeem");
};

const withdrawRequestStatus = async ({ id, arm, vault }) => {
  const queue = await vault.withdrawalQueueMetadata();
  const request = await arm.withdrawalRequests(id);

  if (request.queued <= queue.claimable) {
    console.log(`Withdrawal request ${id} is claimable.`);
  } else {
    console.log(
      `Withdrawal request ${id} is ${formatUnits(
        request.queued - queue.claimable,
      )} short`,
    );
  }
};

const snap = async ({
  arm,
  block,
  days,
  gas,
  amount,
  oneInch,
  kyber,
  route,
  base,
}) => {
  arm = normalizeArmName(arm);
  const armContract = await resolveArmContract(arm);

  const { chainId } = await ethers.provider.getNetwork();

  const blockTag = await getBlock(block);

  const { baseContexts, liquidityBalance, liquidityDecimals } =
    await logLiquidity({
      arm,
      block,
      base,
    });

  if (arm === "EtherFi") {
    await logWithdrawalRequests({ blockTag });
  }

  await logWithdrawalQueue(
    armContract,
    blockTag,
    liquidityBalance,
    liquidityDecimals,
  );

  for (const baseContext of baseContexts) {
    await logSnapForBase({
      arm,
      armContract,
      baseContext,
      block,
      blockTag,
      days,
      gas,
      amount,
      oneInch,
      kyber,
      route,
      chainId,
      liquidityDecimals,
    });
  }
};

const logSnapForBase = async ({
  arm,
  armContract,
  baseContext,
  block,
  blockTag,
  days,
  gas,
  amount,
  oneInch,
  kyber,
  route,
  chainId,
  liquidityDecimals,
}) => {
  const pair =
    arm === "Lido"
      ? `${baseContext.baseSymbol}/WETH`
      : arm === "EtherFi"
        ? `${baseContext.baseSymbol}/WETH`
        : arm === "Ethena"
          ? `${baseContext.baseSymbol}/USDe`
          : arm === "USD"
            ? `${baseContext.baseSymbol}/USDC`
            : arm == "Origin" && chainId === 146
              ? `${baseContext.baseSymbol}/wS`
              : `${baseContext.baseSymbol}/WETH`;
  const armPrices = await logArmPrices(
    { block, blockTag, gas, days, pair, ...baseContext },
    armContract,
  );

  const assets = {
    liquid: baseContext.liquidityAddress,
    base: baseContext.baseAddress,
  };

  let wrapPrice;
  if (arm === "Ethena") {
    const signer = await getSigner();
    wrapPrice = await convertToAsset(assets.base, amount, signer);
    const actualArmSellPrice =
      (armPrices.sellPrice * wrapPrice) / parseUnits("1", 18);
    const actualArmBuyPrice =
      (armPrices.buyPrice * wrapPrice) / parseUnits("1", 18);

    console.log(`\nEthena : ${formatUnits(wrapPrice, 18)} sUSDe/USDe`);
    console.log(
      `Sell   : ${formatUnits(actualArmSellPrice, 18).padEnd(20)} sUSDe/USDe`,
    );
    console.log(
      `Buy    : ${formatUnits(actualArmBuyPrice, 18).padEnd(20)} sUSDe/USDe`,
    );
  }

  if (oneInch) {
    const fee = arm === "Lido" ? 10n : 30n;

    await log1InchPrices(
      {
        amount,
        assets,
        fee,
        pair,
        chainId,
        wrapPrice,
        route,
        liquidityDecimals,
        ...baseContext,
      },
      armPrices,
    );

    if (arm === "EtherFi") {
      await logWrappedEtherFiPrices({ amount, armPrices });
    }
  }

  if (kyber && chainId !== 146) {
    // Kyber does not support Sonic
    await logKyberPrices(
      {
        amount,
        assets,
        pair,
        wrapPrice,
        route,
        liquidityDecimals,
        ...baseContext,
      },
      armPrices,
    );
  }
};

const getLiquidityBaseRows = async ({
  armContract,
  arm,
  base,
  blockTag,
  liquidityDecimals,
}) => {
  const baseSymbols = await getArmBaseSymbols({
    arm: armContract,
    armName: arm,
    base,
    blockTag,
  });
  const armAddress = await armContract.getAddress();

  return Promise.all(
    baseSymbols.map(async (baseSymbol) => {
      const baseContext = await resolveArmBase({
        arm: armContract,
        armName: arm,
        base: baseSymbol,
        blockTag,
      });
      const baseAsset = await ethers.getContractAt(
        "IERC20Metadata",
        baseContext.baseAddress,
      );
      const baseDecimals = Number(await baseAsset.decimals());
      const baseBalance = await baseAsset.balanceOf(armAddress, {
        blockTag,
      });
      const baseBalanceAssets = baseContext.config.peggedToLiquidityAsset
        ? scaleDecimals(baseBalance, baseDecimals, liquidityDecimals)
        : baseContext.config.adapter === ethers.ZeroAddress
          ? await (
              await ethers.getContractAt(
                ["function convertToAssets(uint256) view returns (uint256)"],
                baseContext.baseAddress,
              )
            ).convertToAssets(baseBalance, { blockTag })
          : await (
              await adapterContract(
                baseContext.config.adapter,
                armContract.runner,
              )
            ).convertToAssets(baseBalance);

      return {
        baseContext,
        baseDecimals,
        baseBalance,
        baseBalanceAssets,
        baseWithdraws: baseContext.config.pendingRedeemAssets,
      };
    }),
  );
};

const logLiquidity = async ({ block, arm, base }) => {
  arm = normalizeArmName(arm);
  const blockTag = await getBlock(block);
  console.log(`\nLiquidity`);

  const armContract = await resolveArmContract(arm);
  const armAddress = await armContract.getAddress();

  const liquidityAddress = await armContract.liquidityAsset();
  const liquidAsset = await ethers.getContractAt(
    "IERC20Metadata",
    liquidityAddress,
  );
  const [liquiditySymbol, liquidityDecimalsRaw] = await Promise.all([
    liquidAsset.symbol(),
    liquidAsset.decimals(),
  ]);
  const liquidityDecimals = Number(liquidityDecimalsRaw);
  const liquidityBalance = await liquidAsset.balanceOf(armAddress, {
    blockTag,
  });

  const baseRows = await getLiquidityBaseRows({
    armContract,
    arm,
    blockTag,
    base,
    liquidityDecimals,
  });

  let lendingMarketBalance = 0n;
  let lendingMarketRedeemableBalance = 0n;
  let lendingMarketMaxWithdraw = 0n;
  let morphoRewards = 0n;
  // TODO this can be removed after OETH is upgraded
  if (arm !== "Oeth") {
    // Get the lending market from the active SiloMarket
    const marketAddress = await armContract.activeMarket({ blockTag });
    if (marketAddress !== ethers.ZeroAddress) {
      const market = await ethers.getContractAt(
        "Abstract4626MarketWrapper",
        marketAddress,
      );
      const armShares = await market.balanceOf(armAddress, { blockTag });
      lendingMarketBalance = await market.convertToAssets(armShares, {
        blockTag,
      });
      lendingMarketRedeemableBalance = await market.previewRedeem(armShares, {
        blockTag,
      });
      lendingMarketMaxWithdraw = await market.maxWithdraw(armAddress, {
        blockTag,
      });

      if (arm !== "Ethena") {
        const { amount } = await getMerklRewards({
          userAddress: marketAddress,
        });
        morphoRewards = amount;
      }
    }
  }

  const total =
    liquidityBalance +
    baseRows.reduce(
      (sum, row) => sum + row.baseBalanceAssets + row.baseWithdraws,
      0n,
    ) +
    lendingMarketBalance;
  const liquidityPercent = total == 0 ? 0 : (liquidityBalance * 10000n) / total;
  const lendingMarketPercent =
    total == 0 ? 0 : (lendingMarketBalance * 10000n) / total;

  const totalAssets = await armContract.totalAssets({ blockTag });
  const totalSupply = await armContract.totalSupply({ blockTag });
  const assetPerShare = await armContract.convertToAssets(parseUnits("1"), {
    blockTag,
  });
  const accruedFees = await armContract.feesAccrued({ blockTag });
  const buffer = await getArmBuffer(armContract, blockTag);
  const bufferPercent = (buffer * 10000n) / parseUnits("1");
  const lendingMarketLiquidityShortfall =
    lendingMarketBalance - lendingMarketRedeemableBalance;

  console.log(
    `${formatUnits(
      liquidityBalance,
      liquidityDecimals,
    )} ${liquiditySymbol} ${formatUnits(liquidityPercent, 2)}%`,
  );
  for (const row of baseRows) {
    const basePercent =
      total == 0 ? 0 : (row.baseBalanceAssets * 10000n) / total;
    const baseWithdrawsPercent =
      total == 0 ? 0 : (row.baseWithdraws * 10000n) / total;
    console.log(
      `${formatUnits(row.baseBalance, row.baseDecimals)} ${
        row.baseContext.baseSymbol
      } ${formatUnits(basePercent, 2)}%`,
    );
    console.log(
      `${formatUnits(row.baseWithdraws, liquidityDecimals)} ${
        row.baseContext.baseSymbol
      } in withdrawal requests ${formatUnits(baseWithdrawsPercent, 2)}%`,
    );
  }
  console.log(
    `${formatUnits(
      lendingMarketBalance,
      liquidityDecimals,
    )} ${liquiditySymbol} in active lending market ${formatUnits(
      lendingMarketPercent,
      2,
    )}%`,
  );
  console.log(
    `${formatUnits(
      lendingMarketRedeemableBalance,
      liquidityDecimals,
    )} lending market previewRedeem`,
  );
  console.log(
    `${formatUnits(
      lendingMarketMaxWithdraw,
      liquidityDecimals,
    )} lending market maxWithdraw`,
  );
  console.log(
    `${formatUnits(
      lendingMarketLiquidityShortfall,
      liquidityDecimals,
    )} lending market liquidity shortfall`,
  );
  console.log(`${formatUnits(total, liquidityDecimals)} raw total assets`);

  console.log(`${formatUnits(accruedFees, liquidityDecimals)} accrued fees`);
  console.log(`${formatUnits(totalAssets, liquidityDecimals)} total assets`);
  console.log(`${formatUnits(totalSupply, 18)} total supply`);
  console.log(
    `${formatUnits(assetPerShare, liquidityDecimals)} asset per share`,
  );
  console.log(`liquidity buffer ${formatUnits(bufferPercent, 2)}%`);
  console.log(`${formatUnits(morphoRewards, 18)} MORPHO rewards claimable`);

  return {
    total,
    baseContexts: baseRows.map((row) => row.baseContext),
    liquidityBalance,
    liquidityDecimals,
  };
};

const logWithdrawalQueue = async (
  arm,
  blockTag,
  liquidityBalance,
  liquidityDecimals = 18,
) => {
  const outstanding = await getOutstandingWithdrawals(arm, blockTag);
  const available = liquidityBalance - outstanding;

  console.log(`\nARM Withdrawal Queue`);
  console.log(
    `${formatUnits(outstanding, liquidityDecimals).padEnd(23)} outstanding`,
  );
  console.log(
    `${formatUnits(available, liquidityDecimals).padEnd(23)} available`,
  );
};

module.exports = {
  snap,
  logLiquidity,
  logWithdrawalQueue,
  requestWithdraw,
  claimWithdraw,
  withdrawRequestStatus,
};
