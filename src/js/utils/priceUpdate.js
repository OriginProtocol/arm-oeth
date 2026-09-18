const { formatUnits, parseUnits } = require("ethers");

const { MAX_SWAP_LIQUIDITY } = require("./arm");
const { shouldRefreshBuyCap } = require("./tranchePricing");

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
 * Unlimited target caps never trigger an update by themselves, even after swaps.
 * Finite caps use strict comparison unless `buyCapToleranceBps` is set (2500 =
 * 25%): the buy cap then refreshes when the tranche shrinks or consumption
 * exceeds the tolerance. Finite sell caps always use strict comparison.
 */
const haveSwapCapsChanged = (
  baseContext,
  buyAmount,
  sellAmount,
  { buyCapToleranceBps } = {},
) => {
  if (baseContext.version !== "multiBase") return false;
  const { buyLiquidityRemaining, sellLiquidityRemaining } = baseContext.config;

  const buyChanged =
    buyAmount !== MAX_SWAP_LIQUIDITY &&
    (buyCapToleranceBps === undefined || buyCapToleranceBps === null
      ? buyAmount !== buyLiquidityRemaining
      : shouldRefreshBuyCap({
          remaining: buyLiquidityRemaining,
          target: buyAmount,
          toleranceBps: buyCapToleranceBps,
        }));
  const sellChanged =
    sellAmount !== MAX_SWAP_LIQUIDITY && sellAmount !== sellLiquidityRemaining;

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
