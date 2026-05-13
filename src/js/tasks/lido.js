const { formatUnits, parseUnits } = require("ethers");

const addresses = require("../utils/addresses");
const {
  logArmPrices,
  log1InchPrices,
  logKyberPrices,
  logCurvePrices,
  logUniswapSpotPrices,
  logFluidPrices,
} = require("./markets");
const { getBlock } = require("../utils/block");
const { getLidoQueueData } = require("../utils/lido");
const { getMerklRewards } = require("../utils/merkl");
const { getSigner } = require("../utils/signers");
const { logTxDetails } = require("../utils/txLogger");
const {
  resolveArmContract,
  parseAddress,
  parseDeployedAddress,
} = require("../utils/addressParser");
const { resolveAsset } = require("../utils/assets");
const { adapterContract, resolveArmBase } = require("../utils/arm");
const { logWithdrawalQueue } = require("./liquidity");
const { swap } = require("./swap");

const log = require("../utils/logger")("task:lido");

const lidoWithdrawStatus = async ({ block, id }) => {
  const blockTag = await getBlock(block);
  const lidoWithdrawalQueueAddress = await parseAddress("LIDO_WITHDRAWAL");
  const stEthWithdrawQueue = await hre.ethers.getContractAt(
    "IStETHWithdrawal",
    lidoWithdrawalQueueAddress,
  );

  const status = await stEthWithdrawQueue.getWithdrawalStatus([id], {
    blockTag,
  });

  console.log(
    `Withdrawal request ${id} for ${formatUnits(
      status[0].amountOfStETH,
    )} stETH is finalized ${status[0].isFinalized} and claimed ${
      status[0].isClaimed
    }`,
  );
};

const submitLido = async ({ amount }) => {
  const signer = await getSigner();

  const stethAddress = await parseAddress("STETH");
  //   const steth = await ethers.getContractAt("ISTETH", stethAddress);

  const etherAmount = parseUnits(amount.toString());

  log(`About to send ${amount} ETH to Lido's stETH`);
  const tx = await signer.sendTransaction({
    to: stethAddress,
    value: etherAmount,
  });
  //   const tx = await steth.connect(signer)({ value: etherAmount });
  await logTxDetails(tx, "submit");
};

const snapLido = async ({
  amount,
  block,
  curve,
  oneInch,
  kyber,
  route,
  uniswap,
  gas,
  queue,
  lido,
  user,
  cap,
  fluid,
  base,
}) => {
  const blockTag = await getBlock(block);
  console.log(`\nSnapshot at block ${blockTag}\n`);
  const signer = await getSigner();
  const lidoARM = await resolveArmContract("Lido");
  const baseContext = await resolveArmBase({
    arm: lidoARM,
    armName: "Lido",
    base,
    blockTag,
  });
  const assets = {
    liquid: baseContext.liquidityAddress,
    base: baseContext.baseAddress,
  };
  const commonOptions = {
    amount,
    blockTag,
    pair: `${baseContext.baseSymbol}/ETH`,
    assets,
    fee: 10n,
    chainId: 1n,
    gas,
    signer,
    route,
    ...baseContext,
  };

  const capManagerAddress = await parseDeployedAddress("LIDO_ARM_CAP_MAN");
  const capManager = await ethers.getContractAt(
    "CapManager",
    capManagerAddress,
  );

  const { totalAssets, totalSupply, liquidityWeth } = await logAssets(
    lidoARM,
    blockTag,
    baseContext,
  );
  if (lido) {
    await logLidoQueue(signer, blockTag);

    await logLidoWithdrawals(baseContext.config.adapter, blockTag);
  }
  if (queue) {
    await logWithdrawalQueue(lidoARM, blockTag, liquidityWeth);
  }
  if (user) {
    await logUser(lidoARM, capManager, blockTag, totalSupply);
  }
  if (cap) {
    await logCaps(capManager, totalAssets, blockTag);
  }

  const armPrices = await logArmPrices(commonOptions, lidoARM);

  if (uniswap) {
    const poolName = "wstETH/ETH 0.01%";
    await logUniswapSpotPrices(commonOptions, armPrices, poolName);
  }

  if (curve) {
    await logCurvePrices(
      {
        ...commonOptions,
        poolName: "NextGen",
        poolAddress: addresses.mainnet.CurveNgStEthPool,
      },
      armPrices,
    );

    await logCurvePrices(
      {
        ...commonOptions,
        poolName: "Old",
        poolAddress: addresses.mainnet.CurveStEthPool,
      },
      armPrices,
    );
  }

  if (fluid) {
    const poolName = "wstETH/ETH";
    await logFluidPrices(commonOptions, armPrices, poolName);
  }

  if (kyber) {
    await logKyberPrices(commonOptions, armPrices);
  }

  if (oneInch) {
    await log1InchPrices(commonOptions, armPrices);
  }
};

const logLidoWithdrawals = async (adapterAddress, blockTag) => {
  const lidoWithdrawalQueueAddress = await parseAddress("LIDO_WITHDRAWAL");
  const stEthWithdrawQueue = await hre.ethers.getContractAt(
    "IStETHWithdrawal",
    lidoWithdrawalQueueAddress,
  );
  const outstandingRequests = await stEthWithdrawQueue.getWithdrawalRequests(
    adapterAddress,
    { blockTag },
  );

  console.log(
    `\n${outstandingRequests.length} Lido withdrawal requests: ${outstandingRequests}`,
  );
};

const logLidoQueue = async (signer, blockTag) => {
  const {
    withdrawals,
    deposits,
    elRewards,
    ethFromValidators,
    finalization,
    outstanding,
  } = await getLidoQueueData(signer, blockTag);

  console.log(`\nLido withdrawal queue`);
  console.log(`${formatUnits(withdrawals, 18).padEnd(24)} stETH withdrawals`);
  console.log(`${formatUnits(deposits, 18).padEnd(24)} ETH from deposits`);
  console.log(
    `${formatUnits(elRewards, 18).padEnd(24)} ETH from execution rewards`,
  );
  console.log(
    `${formatUnits(ethFromValidators, 18).padEnd(24)} ETH from validators`,
  );
  console.log(
    `${formatUnits(finalization, 18).padEnd(24)} ETH to be finalized`,
  );
  console.log(`${formatUnits(outstanding, 18).padEnd(24)} ETH outstanding`);
};

const logCaps = async (capManager, totalAssets, blockTag) => {
  const totalAssetsCap = await capManager.totalAssetsCap({ blockTag });
  const capRemaining = totalAssetsCap - totalAssets;
  const capUsedPercent = (totalAssets * 10000n) / totalAssetsCap;

  console.log(`\nCaps`);
  console.log(
    `${formatUnits(totalAssetsCap, 18)} total assets cap, ${formatUnits(
      capUsedPercent,
      2,
    )}% used, ${formatUnits(capRemaining, 18)} remaining`,
  );
};

const logUser = async (arm, capManager, blockTag, totalSupply) => {
  const user = await getSigner();
  console.log(`\nUser ${await user.getAddress()}`);

  const shares = await arm.balanceOf(user.getAddress(), { blockTag });
  const sharesPercentage = (shares * 10000n) / totalSupply;
  const userCap = await capManager.liquidityProviderCaps(user.getAddress(), {
    blockTag,
  });

  console.log(
    `${formatUnits(shares, 18)} shares (${formatUnits(sharesPercentage, 2)}%)`,
  );
  console.log(`${formatUnits(userCap, 18)} cap remaining`);
};

const logAssets = async (arm, blockTag, baseContext) => {
  const weth = await resolveAsset("WETH");
  const liquidityWeth = await weth.balanceOf(arm.getAddress(), { blockTag });

  const baseAsset = await ethers.getContractAt(
    "IERC20Metadata",
    baseContext.baseAddress,
  );
  let lendingMarketBalance = 0n;
  // Get the lending market from the active market
  // Atm we use a hardcoded address, but this should be replaced with a call to the active market once the ARM is upgraded
  let marketAddress = await arm.activeMarket({ blockTag });
  if (marketAddress != addresses.zero) {
    const marketContract = await ethers.getContractAt(
      "Abstract4626MarketWrapper",
      marketAddress,
    );
    const armShares = await marketContract.balanceOf(arm.target, { blockTag });
    lendingMarketBalance = await marketContract.convertToAssets(armShares, {
      blockTag,
    });
    log("Lending market address:", marketAddress);
  }

  const liquidityBase = await baseAsset.balanceOf(arm.getAddress(), {
    blockTag,
  });
  const liquidityBaseAssets = baseContext.config.peggedToLiquidityAsset
    ? liquidityBase
    : await (
        await adapterContract(baseContext.config.adapter, arm.runner)
      ).convertToAssets(liquidityBase);
  const liquidityLidoWithdraws = baseContext.config.pendingRedeemAssets;

  const total =
    liquidityWeth +
    liquidityBaseAssets +
    liquidityLidoWithdraws +
    lendingMarketBalance;
  const wethPercent = total == 0 ? 0 : (liquidityWeth * 10000n) / total;
  const stethWithdrawsPercent =
    total == 0 ? 0 : (liquidityLidoWithdraws * 10000n) / total;
  const basePercent = total == 0 ? 0 : (liquidityBaseAssets * 10000n) / total;
  const lendingMarketPercent =
    total == 0 ? 0 : (lendingMarketBalance * 10000n) / total;
  const totalAssets = await arm.totalAssets({ blockTag });
  const totalSupply = await arm.totalSupply({ blockTag });
  const assetPerShare = await arm.convertToAssets(parseUnits("1"), {
    blockTag,
  });
  const feesAccrued = await arm.feesAccrued({ blockTag });
  const strategistAddress = await parseAddress("STRATEGIST");
  const wethInStrategist = await weth.balanceOf(strategistAddress, {
    blockTag,
  });

  const buffer = await arm.armBuffer({ blockTag });
  const bufferPercent = (buffer * 10000n) / parseUnits("1");

  const { amount: morphoRewards } = await getMerklRewards({
    userAddress: marketAddress,
  });

  console.log(`Assets`);
  console.log(`liquidity buffer ${formatUnits(bufferPercent, 2)}%`);
  console.log(
    `${formatUnits(liquidityWeth, 18).padEnd(24)} WETH  ${formatUnits(
      wethPercent,
      2,
    )}%`,
  );
  console.log(
    `${formatUnits(liquidityBase, 18).padEnd(24)} ${
      baseContext.baseSymbol
    } ${formatUnits(basePercent, 2)}%`,
  );
  console.log(
    `${formatUnits(liquidityLidoWithdraws, 18).padEnd(
      24,
    )} Lido withdraw ${formatUnits(stethWithdrawsPercent, 2)}%`,
  );
  console.log(
    `${formatUnits(lendingMarketBalance, 18).padEnd(
      24,
    )} WETH in active lending market ${formatUnits(lendingMarketPercent, 2)}%`,
  );
  console.log(
    `${formatUnits(total, 18).padEnd(24)} Total WETH and ${
      baseContext.baseSymbol
    }`,
  );
  console.log(`${formatUnits(totalAssets, 18).padEnd(24)} Total assets`);
  console.log(`${formatUnits(totalSupply, 18).padEnd(24)} Total supply`);
  console.log(`${formatUnits(assetPerShare, 18).padEnd(24)} Asset per share`);
  console.log(
    `${formatUnits(feesAccrued, 18).padEnd(24)} Accrued performance fees`,
  );
  console.log(
    `${formatUnits(wethInStrategist, 18).padEnd(24)} WETH in Strategist (fees)`,
  );
  console.log(`${formatUnits(morphoRewards, 18)} MORPHO rewards claimable`);

  return { totalAssets, totalSupply, liquidityWeth };
};

const swapLido = async (options) => swap({ ...options, arm: "Lido" });

module.exports = {
  lidoWithdrawStatus,
  submitLido,
  swapLido,
  snapLido,
};
