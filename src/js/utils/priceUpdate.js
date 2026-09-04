const { formatUnits, parseUnits } = require("ethers");

const { MAX_SWAP_LIQUIDITY } = require("./arm");
const { shouldRefreshBuyCap } = require("./tranchePricing");

// An on-chain liquidity limit at or above this is treated as "uncapped": the
// contract decrements the limit on every swap, so a MAX_SWAP_LIQUIDITY target
// never matches exactly once a swap has happened.
const UNCAPPED_THRESHOLD = 1n << 127n;

const capDexAmountBySwapLiquidity = ({
  amount,
  buyLiquidity,
  sellLiquidity,
  liquidityDecimals,
  baseDecimals,
}) => {
  let cappedAmount = amount.toString();

  if (parseUnits(cappedAmount, liquidityDecimals) > buyLiquidity) {
    cappedAmount = formatUnits(buyLiquidity, liquidityDecimals);
  }
  if (parseUnits(cappedAmount, baseDecimals) > sellLiquidity) {
    cappedAmount = formatUnits(sellLiquidity, baseDecimals);
  }

  return cappedAmount;
};

const resolveDexQuoteAmount = ({
  amount,
  liquidityAssets,
  baseAssetReserve,
  buyLiquidity,
  sellLiquidity,
  liquidityDecimals,
  baseDecimals,
}) => {
  if (amount !== undefined && amount !== null) return amount.toString();

  return capDexAmountBySwapLiquidity({
    amount: formatUnits(liquidityAssets, liquidityDecimals),
    buyLiquidity,
    sellLiquidity:
      baseAssetReserve < sellLiquidity ? baseAssetReserve : sellLiquidity,
    liquidityDecimals,
    baseDecimals,
  });
};

/**
 * Whether the target buy/sell liquidity limits differ from the on-chain ones.
 * Without options the comparison is strict (any difference triggers an update).
 * With `buyCapToleranceBps` (eg 2500 = 25%), the buy limit is only refreshed
 * when the tranche shrank or more than the tolerance was consumed, and an
 * uncapped sell limit is left alone even after swaps decremented it.
 */
const haveSwapCapsChanged = (
  baseContext,
  buyAmount,
  sellAmount,
  { buyCapToleranceBps } = {},
) => {
  if (baseContext.version !== "multiBase") return false;
  const { buyLiquidityRemaining, sellLiquidityRemaining } = baseContext.config;

  if (buyCapToleranceBps === undefined || buyCapToleranceBps === null) {
    return (
      buyAmount !== buyLiquidityRemaining ||
      sellAmount !== sellLiquidityRemaining
    );
  }

  const buyChanged = shouldRefreshBuyCap({
    remaining: buyLiquidityRemaining,
    target: buyAmount,
    toleranceBps: buyCapToleranceBps,
  });
  const sellUncapped =
    sellAmount === MAX_SWAP_LIQUIDITY &&
    sellLiquidityRemaining >= UNCAPPED_THRESHOLD;
  const sellChanged = !sellUncapped && sellAmount !== sellLiquidityRemaining;

  return buyChanged || sellChanged;
};

const exceedsMaxBuyPrice = (targetBuyPrice, maxBuyPrice) =>
  maxBuyPrice !== undefined &&
  maxBuyPrice !== null &&
  targetBuyPrice > parseUnits(maxBuyPrice.toString(), 36);

const fallsBelowMinSellPrice = (targetSellPrice, minSellPrice) =>
  minSellPrice !== undefined &&
  minSellPrice !== null &&
  targetSellPrice < parseUnits(minSellPrice.toString(), 36);

const shouldUpdatePrices = ({
  diffSellPrice,
  diffBuyPrice,
  toleranceScaled,
  buyPriceWasCappedAtMax,
  sellPriceWasFlooredAtMin,
  swapCapsChanged,
}) => {
  const boundedPriceChanged =
    (buyPriceWasCappedAtMax && diffBuyPrice > 0n) ||
    (sellPriceWasFlooredAtMin && diffSellPrice > 0n);

  return (
    diffSellPrice > toleranceScaled ||
    diffBuyPrice > toleranceScaled ||
    boundedPriceChanged ||
    swapCapsChanged
  );
};

module.exports = {
  capDexAmountBySwapLiquidity,
  exceedsMaxBuyPrice,
  fallsBelowMinSellPrice,
  haveSwapCapsChanged,
  resolveDexQuoteAmount,
  shouldUpdatePrices,
};
