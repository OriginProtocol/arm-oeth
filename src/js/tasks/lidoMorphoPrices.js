const { formatUnits, parseUnits } = require("ethers");

const addresses = require("../utils/addresses");

const { abs } = require("../utils/maths");
const { get1InchPrices } = require("../utils/1Inch");
const { logTxDetails } = require("../utils/txLogger");
const { getCurvePrices } = require("../utils/curve");

const log = require("../utils/logger")("task:lido");

const setPrices = async (options) => {
  let {
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
    market,
    priceOffset
  } = options;

  // 1. Get current ARM stETH/WETH prices
  log(`Getting current ARM stETH/WETH prices:`);
  const currentSellPrice = parseUnits("1", 72) / (await arm.traderate0());
  const currentBuyPrice = await arm.traderate1();
  log(`current sell price : ${formatUnits(currentSellPrice, 36)}`);
  log(`current buy price  : ${formatUnits(currentBuyPrice, 36)}`);

  let targetBuyPrice;
  let targetSellPrice;
  // 2. If no buy/sell prices are provided, calculate them using midPrice/1Inch/Curve
  if (!buyPrice && !sellPrice && (midPrice || curve || inch)) {
    // 2.1 Get latest 1inch prices if no midPrice is provided
    const referencePrices =
      // 2.1.a If midPrice is provided, use it directly
      midPrice ?
        {
          midPrice: parseUnits(midPrice.toString(), 18),
        } : // 2.1.b Otherwise, get prices from 1Inch
        inch ?
          await get1InchPrices(options.amount) : // 2.1.c Or from Curve if specified
          await getCurvePrices({
            ...options,
            poolAddress: addresses.mainnet.CurveStEthPool,
          });
    log(`\nReference prices from ${midPrice ? "midPrice" : inch ? "1Inch" : curve ? "Curve" : "unknown source"}:`);
    log(`mid price          : ${formatUnits(referencePrices.midPrice)}`);
    log(`sell price         : ${referencePrices.sellPrice !== undefined ? formatUnits(referencePrices.sellPrice) : "not defined"}`);
    log(`buy price          : ${referencePrices.buyPrice !== undefined ? formatUnits(referencePrices.buyPrice) : "not defined"}`);

    // 2.2 Calculate target prices
    const offsetBN = parseUnits(offset.toString(), 14);
    if (priceOffset && referencePrices.buyPrice) {
      // If price offset is provided, adjust the target prices accordingly
      log(`\nCalculating target prices based on offset:`);
      // Target buy price is the reference buy price plus the offset
      targetBuyPrice = ((referencePrices.buyPrice) + offsetBN) * BigInt(1e18);
      // Target sell price is the target buy price plus 2x fee offset
      targetSellPrice = targetBuyPrice + parseUnits(fee.toString(), 32) * BigInt(2);
      log(`offset             : ${formatUnits(offsetBN, 14)} basis points`);
      log(`fee                : ${formatUnits(BigInt(fee * 1000000), 6)} basis points`);
      log(`target sell price  : ${formatUnits(targetSellPrice, 36)}`);
      log(`target buy price   : ${formatUnits(targetBuyPrice, 36)}`);
    } else {
      // If no price offset, calculate target prices based fee and offset
      log(`\nCalculating target prices based on fee:`);
      const FeeScale = BigInt(1e6);
      const feeRate = FeeScale - BigInt(fee * 100);
      log(
        `fee                : ${formatUnits(
          BigInt(fee * 1000000),
          6
        )} basis points`
      );
      log(`fee rate           : ${formatUnits(feeRate, 6)} basis points`);

      const offsetMidPrice = referencePrices.midPrice - offsetBN;
      log(`offset mid price   : ${formatUnits(offsetMidPrice)}`);

      targetSellPrice = (offsetMidPrice * BigInt(1e18) * FeeScale) / feeRate;
      targetBuyPrice = (offsetMidPrice * BigInt(1e18) * feeRate) / FeeScale;
      log(`target sell price  : ${formatUnits(targetSellPrice, 36)}`);
      log(`target buy price   : ${formatUnits(targetBuyPrice, 36)}`);
    }

    // 2.3 If no min/max prices are provided, calculate them based on the current lending market APY
    if (!minBuyPrice || !maxBuyPrice) {
      log(`\nCalculating min/max buying prices based on current lending market APY:`);
      const currentApyLending = await getLendingMarketAPY(market);
      log(`Current lending APY: ${Number(formatUnits(100n * BigInt(currentApyLending), 18)).toFixed(4)}%`);

      if (!minBuyPrice) {
        minBuyPrice = formatUnits(calculateMinBuyingPrice(currentApyLending), 36);
        log(`min buying price   : ${minBuyPrice}`);

        if (!maxBuyPrice) {
          maxBuyPrice = Number(formatUnits(calculateMaxBuyingPrice(referencePrices.midPrice, minBuyPrice), 36));
          log(`max buying price   : ${maxBuyPrice}`);
        }
      }
    }

    // 2.4 Adjust target prices based on min/max limits
    log(`\nAdjusting target prices based on min/max limits:`);
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
          `target buy price  ${formatUnits(
            targetBuyPrice,
            36
          )} is above max buy price  ${maxBuyPrice} so will use max`
        );
        targetBuyPrice = maxBuyPriceBN;
      }
    }
    if (minBuyPrice) {
      const minBuyPriceBN = parseUnits(minBuyPrice.toString(), 36);
      if (targetBuyPrice < minBuyPriceBN) {
        log(
          `target buy price  ${formatUnits(
            targetBuyPrice,
            36
          )} is below min buy price  ${minBuyPrice} so will use min`
        );
        targetBuyPrice = minBuyPriceBN;
      }
    }

    // 2.5 Adjust target prices based on cross price
    const crossPrice = await arm.crossPrice();
    log(`\nAdjusting target prices based on cross price:`);
    log(`cross price        : ${formatUnits(crossPrice, 36)}`);
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
        `target buy price  ${formatUnits(
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
  log(`\nTarget prices have been calculated:`);
  log(`target sell price  : ${formatUnits(targetSellPrice, 36)}`);
  log(`target buy  price  : ${formatUnits(targetBuyPrice, 36)}`);

  const diffSellPrice = abs(targetSellPrice - currentSellPrice);
  log(`sell price diff    : ${formatUnits(diffSellPrice, 32)} basis points`);
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

/**
 * Get the current APY from the ARM's active lending market
 */
const getLendingMarketAPY = async (market) => {

  // Get the underlying Morpho market address
  //const underlyingMorphoMarket = await market.market();
  const underlyingMorphoMarket = "0x9a8bC3B04b7f3D87cfC09ba407dCED575f2d61D8"; // Hardcoded for Morpho market, waiting for deployment

  const query = `query {
    vaultByAddress(
      address: "${underlyingMorphoMarket}"
      chainId: 1
    ) {
      address
      asset {
        yield {
          apr
        }
      }
      state {
        apy
        netApy
        netApyWithoutRewards
        dailyApy
        dailyNetApy
        weeklyApy
        weeklyNetApy
        monthlyApy
        monthlyNetApy
        rewards {
          asset {
            address
          }
          supplyApr
          yearlySupplyTokens
        }
        allocation {
          supplyAssets
          supplyAssetsUsd
          market {
            uniqueKey
            state {
              rewards {
                asset {
                  address
                }
                supplyApr
                borrowApr
              }
            }
          }
        }
      }
    }
  }`;

  // TODO: Make sure it can work for non-Silo markets later
  const response = await fetch(`https://api.morpho.org/graphql`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      query
    }),
  });
  const data = await response.json();

  // APR scaled to 1e6
  const apr = Number((1000000n * BigInt(Math.floor(data.data.vaultByAddress.state.weeklyNetApy * 1e18))) / BigInt(1e18));
  log(`Current lending APR: ${Number(formatUnits(100n * BigInt(apr), 6)).toFixed(4)}%`);

  const dailyRate = apr / 365 / 1000000;
  const apy = Math.pow(1 + dailyRate, 365) - 1;

  // Scale back to 18 decimals
  return parseUnits(apy.toString(), 18);
};

/**
 * Calculate minimum buying price based on APY
 *  Formula: 1/(1+apy) ^ (1 / (365 / 15))
 *  Where 15 is the number of days in the holding period
 */
const calculateMinBuyingPrice = (lendingAPY) => {
  // Scale BN to decimal to make calculations easier
  const apyNumber = Number(formatUnits(lendingAPY, 18))

  const daysPeriod = 15;
  const exponent = daysPeriod / 365;

  // 1/(1+apy) ^ (1 / (365 / 15))
  const minPrice = 1 / Math.pow(1 + apyNumber, exponent);

  // Convert back to 36 decimals for ARM pricing
  const minPriceScaled = parseUnits(minPrice.toString(), 36);

  // Ensure we don't go below a reasonable minimum (0.99)
  const minAllowed = parseUnits("0.99", 36);
  return minPriceScaled > minAllowed ? minPriceScaled : minAllowed;
};

const calculateMaxBuyingPrice = (marketPrice, minBuyingPrice) => {
  // Scale market price to 36 decimals for ARM pricing
  const marketPriceScaled = marketPrice * parseUnits("1", 18);

  // Add a small premium to market price (0.1 basis points = 0.001%)
  const premium = marketPriceScaled * 1n / 100000n; // 0.001%
  const maxPrice = marketPriceScaled + premium;

  minBuyingPrice = parseUnits(minBuyingPrice.toString(), 36);
  // Ensure it doesn't exceed the minimum buying price
  // The max buying price must be below minBuyingPrice to maintain profitability
  log(
    `max buying price     ${formatUnits(maxPrice, 36)} is ${maxPrice < minBuyingPrice ? "below" : "above or equal to"
    } min buying price ${formatUnits(minBuyingPrice, 36)} so will use ${maxPrice < minBuyingPrice ? "max buying price" : "min buying price"
    }`
  );
  return maxPrice < minBuyingPrice ? maxPrice : minBuyingPrice;
};


module.exports = {
  setPrices,
};