const { formatUnits, parseUnits } = require("ethers");

const addresses = require("../utils/addresses");

const { abs } = require("../utils/maths");
const { get1InchPrices } = require("../utils/1Inch");
const { logTxDetails } = require("../utils/txLogger");
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
    maxSellPrice,
    minBuyPrice,
    maxBuyPrice,
    offset,
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

    const offsetBN = parseUnits(offset.toString(), 14);
    const offsetMidPrice = referencePrices.midPrice - offsetBN;
    log(`offset mid price   : ${formatUnits(offsetMidPrice)}`);

    const FeeScale = BigInt(1e6);
    const feeRate = FeeScale - BigInt(fee * 100);
    log(
      `fee                : ${formatUnits(
        BigInt(fee * 1000000),
        6
      )} basis points`
    );
    log(`fee rate           : ${formatUnits(feeRate, 6)} basis points`);

    targetSellPrice = (offsetMidPrice * BigInt(1e18) * FeeScale) / feeRate;
    targetBuyPrice = (offsetMidPrice * BigInt(1e18) * feeRate) / FeeScale;

    if (maxSellPrice) {
      const maxSellPriceBN = parseUnits(maxSellPrice.toString(), 36);
      if (targetSellPrice > maxSellPriceBN) {
        log(
          `target sell price ${formatUnits(
            targetSellPrice,
            36
          )} is above max sell price ${maxSellPrice} so will use max`
        );
        targetSellPrice = maxSellPriceBN;
      }
    }
    if (minSellPrice) {
      const minSellPriceBN = parseUnits(minSellPrice.toString(), 36);
      if (targetSellPrice < minSellPriceBN) {
        log(
          `target sell price ${formatUnits(
            targetSellPrice,
            36
          )} is below min sell price ${minSellPrice} so will use min`
        );
        targetSellPrice = minSellPriceBN;
      }
    }
    if (maxBuyPrice) {
      const maxBuyPriceBN = parseUnits(maxBuyPrice.toString(), 36);
      if (targetBuyPrice > maxBuyPriceBN) {
        log(
          `target buy price ${formatUnits(
            targetBuyPrice,
            36
          )} is above max buy price ${maxBuyPrice} so will use max`
        );
        targetBuyPrice = maxBuyPriceBN;
      }
    }
    if (minBuyPrice) {
      const minBuyPriceBN = parseUnits(minBuyPrice.toString(), 36);
      if (targetBuyPrice < minBuyPriceBN) {
        log(
          `target buy price ${formatUnits(
            targetBuyPrice,
            36
          )} is below min buy price ${minBuyPrice} so will use min`
        );
        targetBuyPrice = minBuyPriceBN;
      }
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
  log(`sell price diff     : ${formatUnits(diffSellPrice, 32)} basis points`);
  const diffBuyPrice = abs(targetBuyPrice - currentBuyPrice);
  log(`buy price diff     : ${formatUnits(diffBuyPrice, 32)} basis points`);

  // tolerance option is in basis points
  const toleranceScaled = parseUnits(tolerance.toString(), 36 - 4);
  log(`tolerance          : ${formatUnits(toleranceScaled, 32)} basis points`);

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

module.exports = {
  setPrices,
};
