const { formatUnits, parseUnits, MaxInt256 } = require("ethers");

const addresses = require("../utils/addresses");
const {
  logArmPrices,
  log1InchPrices,
  logCurvePrices,
  logUniswapSpotPrices,
} = require("./markets");
const { getBlock } = require("../utils/block");
const { abs } = require("../utils/maths");
const { get1InchPrices } = require("../utils/1Inch");
const { getSigner } = require("../utils/signers");
const { logTxDetails } = require("../utils/txLogger");
const {
  parseAddress,
  parseDeployedAddress,
} = require("../utils/addressParser");
const { resolveAddress, resolveAsset } = require("../utils/assets");
const { getCurvePrices } = require("../utils/curve");

const log = require("../utils/logger")("task:lido");

const setPrices = async (options) => {
  const {
    signer,
    arm,
    fee,
    tolerance,
    buyPrice,
    midPrice,
    sellPrice,
    minSellPrice,
    maxBuyPrice,
    curve,
    inch,
  } = options;

  // get current ARM stETH/WETH prices
  const currentSellPrice = parseUnits("1", 72) / (await arm.traderate0());
  const currentBuyPrice = await arm.traderate1();
  log(`current sell price : ${formatUnits(currentSellPrice, 36)}`);
  log(`current buy price  : ${formatUnits(currentBuyPrice, 36)}`);

  let targetSellPrice;
  let targetBuyPrice;
  if (!buyPrice && !sellPrice && (midPrice || curve || inch)) {
    // get latest 1inch prices if no midPrice is provided
    const referencePrices = midPrice
      ? {
          midPrice: parseUnits(midPrice.toString(), 18),
        }
      : inch
      ? await get1InchPrices(options.amount)
      : await getCurvePrices({
          ...options,
          poolAddress: addresses.mainnet.CurveStEthPool,
        });
    log(`mid price          : ${formatUnits(referencePrices.midPrice)}`);

    const FeeScale = BigInt(1e6);
    const feeRate = FeeScale - BigInt(fee * 100);
    log(`fee                : ${formatUnits(BigInt(fee * 1000000), 6)} bps`);
    log(`fee rate           : ${formatUnits(feeRate, 6)} bps`);

    targetSellPrice =
      (referencePrices.midPrice * BigInt(1e18) * FeeScale) / feeRate;
    targetBuyPrice =
      (referencePrices.midPrice * BigInt(1e18) * feeRate) / FeeScale;

    const minSellPriceBN = parseUnits(minSellPrice.toString(), 36);
    const maxBuyPriceBN = parseUnits(maxBuyPrice.toString(), 36);
    if (targetSellPrice < minSellPriceBN) {
      log(
        `target sell price ${formatUnits(
          targetSellPrice,
          36
        )} is below min sell price ${minSellPrice} so will use min`
      );
      targetSellPrice = minSellPriceBN;
    }
    if (targetBuyPrice > maxBuyPriceBN) {
      log(
        `target buy price ${formatUnits(
          targetBuyPrice,
          36
        )} is above max buy price ${maxBuyPrice} so will use max`
      );
      targetBuyPrice = maxBuyPriceBN;
    }

    const crossPrice = await arm.crossPrice();
    if (targetSellPrice < crossPrice) {
      log(
        `target sell price ${formatUnits(
          targetSellPrice,
          36
        )} is below cross price ${formatUnits(
          crossPrice,
          36
        )} so will use cross price`
      );
      targetSellPrice = crossPrice;
    }
    if (targetBuyPrice >= crossPrice) {
      log(
        `target buy price ${formatUnits(
          targetBuyPrice,
          36
        )} is above cross price ${formatUnits(
          crossPrice,
          36
        )} so will use cross price`
      );
      targetBuyPrice = crossPrice - 1n;
    }
  } else if (buyPrice && sellPrice) {
    targetSellPrice = parseUnits(sellPrice.toString(), 18) * BigInt(1e18);
    targetBuyPrice = parseUnits(buyPrice.toString(), 18) * BigInt(1e18);
  } else {
    throw new Error(
      `Either both buy and sell prices should be provided or midPrice`
    );
  }

  log(`target sell price  : ${formatUnits(targetSellPrice, 36)}`);
  log(`target buy  price  : ${formatUnits(targetBuyPrice, 36)}`);

  const diffSellPrice = abs(targetSellPrice - currentSellPrice);
  log(`sell price diff     : ${formatUnits(diffSellPrice, 36)}`);
  const diffBuyPrice = abs(targetBuyPrice - currentBuyPrice);
  log(`buy price diff     : ${formatUnits(diffBuyPrice, 36)}`);

  // tolerance option is in basis points
  const toleranceScaled = parseUnits(tolerance.toString(), 36 - 4);
  log(`tolerance          : ${formatUnits(toleranceScaled, 36)}`);

  // decide if rates need to be updated
  if (diffSellPrice > toleranceScaled || diffBuyPrice > toleranceScaled) {
    console.log(`About to update ARM prices`);
    console.log(`sell: ${formatUnits(targetSellPrice, 36)}`);
    console.log(`buy : ${formatUnits(targetBuyPrice, 36)}`);

    const tx = await arm
      .connect(signer)
      .setPrices(targetBuyPrice, targetSellPrice);

    await logTxDetails(tx, "setPrices", options.confirm);
  } else {
    console.log(
      `No price update as price diff of buy ${formatUnits(
        diffBuyPrice,
        32
      )} and sell ${formatUnits(diffSellPrice, 32)} < tolerance ${formatUnits(
        toleranceScaled,
        32
      )} basis points`
    );
  }
};

async function setZapper() {
  const signer = await getSigner();

  const lidoArmAddress = await parseDeployedAddress("LIDO_ARM");
  const lidoARM = await ethers.getContractAt("LidoARM", lidoArmAddress);

  const zapperAddress = await parseDeployedAddress("LIDO_ARM_ZAPPER");

  log(`About to set the Zapper contract on the Lido ARM to ${zapperAddress}`);
  const tx = await lidoARM.connect(signer).setZap(zapperAddress);
  await logTxDetails(tx, "setZap");
}

const lidoWithdrawStatus = async ({ id }) => {
  const lidoWithdrawalQueueAddress = await parseAddress("LIDO_WITHDRAWAL");
  const stEthWithdrawQueue = await hre.ethers.getContractAt(
    "IStETHWithdrawal",
    lidoWithdrawalQueueAddress
  );

  const status = await stEthWithdrawQueue.getWithdrawalStatus([id]);

  console.log(
    `Withdrawal request ${id} is finalized ${status[0].isFinalized} and claimed ${status[0].isClaimed}`
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

const snapLido = async ({ amount, block, curve, oneInch, uniswap, gas }) => {
  const blockTag = await getBlock(block);
  const commonOptions = { amount, blockTag, pair: "stETH/ETH", gas };

  const armAddress = await parseAddress("LIDO_ARM");
  const lidoARM = await ethers.getContractAt("LidoARM", armAddress);
  const capManagerAddress = await parseDeployedAddress("LIDO_ARM_CAP_MAN");
  const capManager = await ethers.getContractAt(
    "CapManager",
    capManagerAddress
  );

  const ammPrices = await logArmPrices(commonOptions, lidoARM);

  if (oneInch) {
    await log1InchPrices(commonOptions, ammPrices);
  }

  if (curve) {
    await logCurvePrices(
      {
        ...commonOptions,
        poolName: "Old",
        poolAddress: addresses.mainnet.CurveStEthPool,
      },
      ammPrices
    );

    await logCurvePrices(
      {
        ...commonOptions,
        poolName: "NextGen",
        poolAddress: addresses.mainnet.CurveNgStEthPool,
      },
      ammPrices
    );
  }

  if (uniswap) {
    await logUniswapSpotPrices(commonOptions, ammPrices);
  }

  const { totalAssets, totalSupply, liquidityWeth } = await logAssets(
    lidoARM,
    blockTag
  );
  await logWithdrawalQueue(lidoARM, blockTag, liquidityWeth);
  await logUser(lidoARM, capManager, blockTag, totalSupply);
  await logCaps(capManager, totalAssets, blockTag);
};

const logCaps = async (capManager, totalAssets, blockTag) => {
  const totalAssetsCap = await capManager.totalAssetsCap({ blockTag });
  const capRemaining = totalAssetsCap - totalAssets;
  const capUsedPercent = (totalAssets * 10000n) / totalAssetsCap;

  console.log(`\nCaps`);
  console.log(
    `${formatUnits(totalAssetsCap, 18)} total assets cap, ${formatUnits(
      capUsedPercent,
      2
    )}% used, ${formatUnits(capRemaining, 18)} remaining`
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
    `${formatUnits(shares, 18)} shares (${formatUnits(sharesPercentage, 2)}%)`
  );
  console.log(`${formatUnits(userCap, 18)} cap remaining`);
};

const logWithdrawalQueue = async (arm, blockTag, liquidityWeth) => {
  const queue = await arm.withdrawsQueued({
    blockTag,
  });
  const claimed = await arm.withdrawsClaimed({ blockTag });
  const outstanding = queue - claimed;
  const shortfall =
    liquidityWeth < outstanding ? liquidityWeth - outstanding : 0;

  console.log(`\nARM Withdrawal Queue`);
  console.log(`${formatUnits(outstanding, 18)} outstanding`);
  console.log(`${formatUnits(shortfall, 18)} shortfall`);
};

const logAssets = async (arm, blockTag) => {
  const armBuybackAddress = await parseAddress("ARM_BUYBACK");
  const weth = await resolveAsset("WETH");
  const liquidityWeth = await weth.balanceOf(arm.getAddress(), { blockTag });
  const armBuybackWeth = await weth.balanceOf(armBuybackAddress, { blockTag });

  const steth = await resolveAsset("STETH");
  const liquiditySteth = await steth.balanceOf(arm.getAddress(), { blockTag });
  const liquidityLidoWithdraws = await arm.lidoWithdrawalQueueAmount({
    blockTag,
  });

  const total = liquidityWeth + liquiditySteth + liquidityLidoWithdraws;
  const wethPercent = total == 0 ? 0 : (liquidityWeth * 10000n) / total;
  const stethWithdrawsPercent =
    total == 0 ? 0 : (liquidityLidoWithdraws * 10000n) / total;
  const oethPercent = total == 0 ? 0 : (liquiditySteth * 10000n) / total;
  const totalAssets = await arm.totalAssets({ blockTag });
  const totalSupply = await arm.totalSupply({ blockTag });
  const assetPerShare = await arm.convertToAssets(parseUnits("1"), {
    blockTag,
  });
  const feesAccrued = await arm.feesAccrued({ blockTag });

  console.log(`\nAssets`);
  console.log(
    `${formatUnits(liquidityWeth, 18).padEnd(23)} WETH  ${formatUnits(
      wethPercent,
      2
    )}%`
  );
  console.log(
    `${formatUnits(liquiditySteth, 18).padEnd(23)} stETH ${formatUnits(
      oethPercent,
      2
    )}%`
  );
  console.log(
    `${formatUnits(liquidityLidoWithdraws, 18).padEnd(
      23
    )} Lido withdraw ${formatUnits(stethWithdrawsPercent, 2)}%`
  );
  console.log(`${formatUnits(total, 18).padEnd(23)} total WETH and stETH`);
  console.log(`${formatUnits(totalAssets, 18).padEnd(23)} total assets`);
  console.log(`${formatUnits(totalSupply, 18).padEnd(23)} total supply`);
  console.log(`${formatUnits(assetPerShare, 18).padEnd(23)} asset per share`);
  console.log(
    `${formatUnits(feesAccrued, 18).padEnd(23)} accrued performance fees`
  );
  console.log(`${formatUnits(armBuybackWeth, 18).padEnd(23)} WETH in Buyback`);

  return { totalAssets, totalSupply, liquidityWeth };
};

const swapLido = async ({ from, to, amount }) => {
  if (from && to) {
    throw new Error(
      `Cannot specify both from and to asset. It has to be one or the other`
    );
  }
  const signer = await getSigner();
  const signerAddress = await signer.getAddress();

  const armAddress = await parseAddress("LIDO_ARM");
  const lidoARM = await ethers.getContractAt("LidoARM", armAddress);

  if (from) {
    const fromAddress = await resolveAddress(from.toUpperCase());

    const to = from === "stETH" ? "WETH" : "stETH";
    const toAddress = await resolveAddress(to.toUpperCase());

    const fromAmount = parseUnits(amount.toString(), 18);

    log(`About to swap ${amount} ${from} to ${to} for ${signerAddress}`);

    const tx = await lidoARM
      .connect(signer)
      ["swapExactTokensForTokens(address,address,uint256,uint256,address)"](
        fromAddress,
        toAddress,
        fromAmount,
        0,
        signerAddress
      );

    await logTxDetails(tx, "swap exact from");
  } else if (to) {
    const from = to === "stETH" ? "WETH" : "stETH";
    const fromAddress = await resolveAddress(from.toUpperCase());

    const toAddress = await resolveAddress(to.toUpperCase());

    const toAmount = parseUnits(amount.toString(), 18);

    log(`About to swap ${from} to ${amount} ${to} for ${signerAddress}`);

    const tx = await lidoARM
      .connect(signer)
      ["swapTokensForExactTokens(address,address,uint256,uint256,address)"](
        fromAddress,
        toAddress,
        toAmount,
        MaxInt256,
        signerAddress
      );

    await logTxDetails(tx, "swap exact to");
  } else {
    throw new Error(`Must specify either from or to asset`);
  }
};

module.exports = {
  lidoWithdrawStatus,
  submitLido,
  swapLido,
  snapLido,
  setPrices,
  setZapper,
};
