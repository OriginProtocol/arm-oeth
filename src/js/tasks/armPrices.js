const { Contract, formatUnits, parseUnits, ZeroAddress } = require("ethers");

const addresses = require("../utils/addresses");
const {
  adapterContract,
  parseSwapCap,
  resolveArmBase,
  setArmPrices,
} = require("../utils/arm");
const { abs } = require("../utils/maths");
const { getCurvePrices } = require("../utils/curve");
const { getKyberPrices } = require("../utils/kyber");
const { get1InchPrices } = require("../utils/1Inch");
const { logTxDetails } = require("../utils/txLogger");
const {
  convertToAsset,
  calculatePriceOffset,
  rangeSellPrice,
  rangeBuyPrice,
} = require("../utils/pricing");

const log = require("../utils/logger")("task:prices");

// Scale a token amount to 18 decimals so ratios between amounts of assets
// with different decimals (6 or 18) stay 1e18-scaled.
const scaleTo18 = (value, decimals) => value * 10n ** BigInt(18 - decimals);

/**
 *
 * @param {*} options
 * signer - ethers signer to send transactions
 * arm - name of the ARM. eg Lido, EtherFi, Ethena, OETH
 * fee - basis points from mid price or spread if using offset
 * tolerance - basis points difference between current and target prices to trigger an update
 * buyPrice - target buy price (optional if midPrice or market data is provided)
 * sellPrice - target sell price (optional if midPrice or market data is provided)
 * midPrice - reference mid price to calculate buy/sell prices from (optional if buy/sell prices are provided)
 * curve/inch/kyber - whether to use Curve/1Inch/Kyber for reference prices
 * market - Ethers contract of the ARM's active lending market. Only used for Morpho markets
 * offset - price offset in basis points to add to the reference buy price when calculating target prices
 * dynamicOffset - if true, scale the offset from 0 to the DEX spread based on distance from cross price
 * dynamicOffsetFullSpreadPrice - price where dynamic offset reaches 100% of the DEX spread
 * priceOffset - whether to use the offset-based approach for calculating target prices, or just calculate off the reference mid price and fee
 * dryrun - if true, will not actually call setPrices on the ARM, just log the target prices
 * base - base asset symbol. eg STETH, WSTETH, EETH, WEETH, SUSDE, OETH, WOETH, OS
 * wrapped - adjust market prices by the adapter conversion rate
 * @returns
 */
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
    kyber,
    market,
    priceOffset,
    dryrun,
    base,
    wrapped,
    buyAmount,
    sellAmount,
    dynamicOffset,
    dynamicOffsetFullSpreadPrice,
  } = options;

  // 1. Get current ARM prices
  const baseContext = await resolveArmBase({
    arm,
    armName: options.armName,
    base,
    blockTag: options.blockTag,
  });
  const { baseSymbol, baseAddress, liquidityAddress, config } = baseContext;
  const shouldAdjustWrapped =
    wrapped !== undefined ? wrapped : !config.peggedToLiquidityAsset;
  // Base asset decimals used to scale aggregator quote amounts. Legacy ARM
  // configs don't expose baseAssetDecimals as all their assets are 18 decimals.
  const baseDecimals = Number(config.baseAssetDecimals ?? 18);

  log(`Getting current ARM prices:`);
  log(`base asset         : ${baseSymbol}`);
  const currentSellPrice = config.sellPrice;
  const currentBuyPrice = config.buyPrice;
  log(`current sell price : ${formatUnits(currentSellPrice, 36)}`);
  log(`current buy price  : ${formatUnits(currentBuyPrice, 36)}`);

  let targetBuyPrice;
  let targetSellPrice;
  // 2. If no buy/sell prices are provided, calculate them using midPrice/1Inch/Curve
  if (!buyPrice && !sellPrice && (midPrice || curve || inch || kyber)) {
    // Set asset options
    const assets = {
      liquid: liquidityAddress,
      base: baseAddress,
    };
    const inchFee =
      assets.base.toLowerCase() === addresses.mainnet.stETH.toLowerCase() ||
      assets.base.toLowerCase() === addresses.mainnet.wstETH.toLowerCase()
        ? 10n
        : 30n;

    // The liquidity asset decimals are not in the base asset config so read
    // them on-chain. Can differ from the base asset decimals, eg an 18
    // decimals base asset over a 6 decimals USDC liquidity asset.
    const liquidityDecimals = Number(
      await new Contract(
        liquidityAddress,
        ["function decimals() view returns (uint8)"],
        signer,
      ).decimals(),
    );

    // 2.1 Get reference prices
    let referencePrices;
    if (midPrice) {
      // 2.1.a If midPrice is provided, use it directly
      referencePrices = {
        midPrice: parseUnits(midPrice.toString(), 18),
      };
    } else {
      if (curve && options.armName !== "Lido")
        throw new Error(`Curve prices only available for Lido`);

      // 2.1 Get latest market prices if no midPrice is provided
      referencePrices = inch
        ? // 2.1.b Otherwise, get prices from 1Inch
          await get1InchPrices(
            options.amount,
            assets,
            inchFee,
            1,
            baseDecimals,
            liquidityDecimals,
          )
        : kyber
          ? // 2.1.c Or from Kyber if specified
            await getKyberPrices(
              options.amount,
              assets,
              baseDecimals,
              liquidityDecimals,
            )
          : // 2.1.d Or from Curve if specified
            await getCurvePrices({
              ...options,
              poolAddress: addresses.mainnet.CurveNgStEthPool,
            });

      // Adjust price down if a wrapped asset like sUSDe or wstETH
      if (shouldAdjustWrapped) {
        const amountIn = parseUnits(options.amount.toString(), baseDecimals);
        // The legacy convertToAsset path returns 18 decimals while the adapter
        // converts a base decimals input to liquidity decimals
        const convertedAssets =
          config.adapter === ZeroAddress
            ? await convertToAsset(baseAddress, options.amount, signer)
            : await (
                await adapterContract(config.adapter, signer)
              ).convertToAssets(amountIn);
        const convertedDecimals =
          config.adapter === ZeroAddress ? 18 : liquidityDecimals;
        const wrapPrice =
          (scaleTo18(convertedAssets, convertedDecimals) * parseUnits("1")) /
          scaleTo18(amountIn, baseDecimals);

        log(`Base asset price : ${formatUnits(wrapPrice, 18)} base/liquid`);

        referencePrices.sellPrice =
          (referencePrices.sellPrice * parseUnits("1", 18)) / wrapPrice;
        referencePrices.midPrice =
          (referencePrices.midPrice * parseUnits("1", 18)) / wrapPrice;
        referencePrices.buyPrice =
          (referencePrices.buyPrice * parseUnits("1", 18)) / wrapPrice;
      }
    }

    log(
      `\nReference prices from ${
        midPrice
          ? "midPrice"
          : inch
            ? "1Inch"
            : kyber
              ? "Kyber"
              : curve
                ? "Curve"
                : "unknown source"
      }:`,
    );
    log(`mid price          : ${formatUnits(referencePrices.midPrice)}`);
    log(
      `sell price         : ${
        referencePrices.sellPrice !== undefined
          ? formatUnits(referencePrices.sellPrice)
          : "not defined"
      }`,
    );
    log(
      `buy price          : ${
        referencePrices.buyPrice !== undefined
          ? formatUnits(referencePrices.buyPrice)
          : "not defined"
      }`,
    );

    // 2.2 Calculate target prices
    if (priceOffset && referencePrices.sellPrice) {
      const offsetBN = calculatePriceOffset({
        offset,
        dynamicOffset,
        dynamicOffsetFullSpreadPrice,
        referencePrices,
        crossPrice: config.crossPrice,
      });
      const dexSpread =
        referencePrices.buyPrice > referencePrices.sellPrice
          ? referencePrices.buyPrice - referencePrices.sellPrice
          : 0n;
      // If price offset is provided, adjust the target prices accordingly
      log(`\nCalculating target prices based on offset:`);
      // Target buy price is the reference sell price plus the offset
      targetBuyPrice = (referencePrices.sellPrice + offsetBN) * BigInt(1e18);
      // Target sell price is the target buy price plus 2x fee offset
      targetSellPrice =
        targetBuyPrice + parseUnits(fee.toString(), 32) * BigInt(2);
      log(`offset             : ${formatUnits(offsetBN, 14)} basis points`);
      if (dynamicOffset) {
        log(
          `dynamic offset     : full spread at ${dynamicOffsetFullSpreadPrice}`,
        );
        log(`DEX spread         : ${formatUnits(dexSpread, 18)}`);
      }
      log(
        `fee                : ${formatUnits(
          BigInt(fee * 1000000),
          6,
        )} basis points`,
      );
      log(`target sell price  : ${formatUnits(targetSellPrice, 36)}`);
      log(`target buy price   : ${formatUnits(targetBuyPrice, 36)}`);
    } else {
      const offsetBN = parseUnits(offset.toString(), 14);
      // If no price offset, calculate target prices based fee and offset
      log(`\nCalculating target prices based on fee:`);
      const FeeScale = BigInt(1e6);
      const feeRate = FeeScale - BigInt(fee * 100);
      log(
        `fee                : ${formatUnits(
          BigInt(fee * 1000000),
          6,
        )} basis points`,
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
    if ((!minBuyPrice || !maxBuyPrice) && market) {
      log(
        `\nCalculating min/max buying prices based on current lending market APY:`,
      );
      const currentApyLending = await getLendingMarketAPY(market);
      log(
        `Current lending APY: ${Number(
          formatUnits(100n * BigInt(currentApyLending), 18),
        ).toFixed(4)}%`,
      );

      if (!minBuyPrice) {
        minBuyPrice = formatUnits(
          calculateMinBuyingPrice(currentApyLending),
          36,
        );
        log(`min buying price   : ${minBuyPrice}`);

        if (!maxBuyPrice) {
          maxBuyPrice = Number(
            formatUnits(
              calculateMaxBuyingPrice(referencePrices.midPrice, minBuyPrice),
              36,
            ),
          );
          log(`max buying price   : ${maxBuyPrice}`);
        }
      }
    }

    // 2.4 Adjust target prices based on min/max limits
    targetSellPrice = rangeSellPrice(
      targetSellPrice,
      minSellPrice,
      maxSellPrice,
    );
    targetBuyPrice = rangeBuyPrice(targetBuyPrice, minBuyPrice, maxBuyPrice);

    // 2.5 Adjust target prices based on cross price
    const crossPrice = config.crossPrice;
    log(`\nAdjusting target prices based on cross price:`);
    log(`cross price        : ${formatUnits(crossPrice, 36)}`);
    if (targetSellPrice < crossPrice) {
      log(
        `target sell price ${formatUnits(
          targetSellPrice,
          36,
        )} is below cross price ${formatUnits(
          crossPrice,
          36,
        )} so will use cross price`,
      );
      targetSellPrice = crossPrice;
    }
    if (targetBuyPrice >= crossPrice) {
      log(
        `target buy price  ${formatUnits(
          targetBuyPrice,
          36,
        )} is above cross price ${formatUnits(
          crossPrice,
          36,
        )} so will use cross price`,
      );
      targetBuyPrice = crossPrice - 1n;
    }
  } else if (buyPrice && sellPrice) {
    targetSellPrice = parseUnits(sellPrice.toString(), 18) * BigInt(1e18);
    targetBuyPrice = parseUnits(buyPrice.toString(), 18) * BigInt(1e18);
  } else {
    throw new Error(
      `Either both buy and sell prices should be provided or midPrice`,
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

    if (dryrun) {
      console.log(`Dry run mode - not calling setPrices`);
      return;
    }

    const tx = await setArmPrices({
      baseContext,
      signer,
      buyPrice: targetBuyPrice,
      sellPrice: targetSellPrice,
      buyAmount: parseSwapCap(buyAmount),
      sellAmount: parseSwapCap(sellAmount),
    });

    await logTxDetails(tx, "setPrices", options.confirm);
  } else {
    console.log(
      `No price update as price diff of buy ${formatUnits(
        diffBuyPrice,
        32,
      )} and sell ${formatUnits(diffSellPrice, 32)} < tolerance ${formatUnits(
        toleranceScaled,
        32,
      )} basis points`,
    );
  }
};

/**
 * Get the current APY from the ARM's active lending market
 */
const getLendingMarketAPY = async (market) => {
  if (!market) return 0n;
  // Get the underlying Morpho market address
  const underlyingMorphoMarket = await market.market();

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
      query,
    }),
  });
  const data = await response.json();

  // APR scaled to 1e6
  const apr = Number(
    (1000000n *
      BigInt(Math.floor(data.data.vaultByAddress.state.weeklyNetApy * 1e18))) /
      BigInt(1e18),
  );
  log(
    `Current lending APR: ${Number(formatUnits(100n * BigInt(apr), 6)).toFixed(
      4,
    )}%`,
  );

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
  const apyNumber = Number(formatUnits(lendingAPY, 18));

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
  const premium = (marketPriceScaled * 1n) / 100000n; // 0.001%
  const maxPrice = marketPriceScaled + premium;

  minBuyingPrice = parseUnits(minBuyingPrice.toString(), 36);
  // Ensure it doesn't exceed the minimum buying price
  // The max buying price must be below minBuyingPrice to maintain profitability
  log(
    `max buying price     ${formatUnits(maxPrice, 36)} is ${
      maxPrice < minBuyingPrice ? "below" : "above or equal to"
    } min buying price ${formatUnits(minBuyingPrice, 36)} so will use ${
      maxPrice < minBuyingPrice ? "max buying price" : "min buying price"
    }`,
  );
  return maxPrice < minBuyingPrice ? maxPrice : minBuyingPrice;
};

module.exports = {
  setPrices,
};
