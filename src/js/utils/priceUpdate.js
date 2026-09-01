const { formatUnits, parseUnits } = require("ethers");

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

const haveSwapCapsChanged = (baseContext, buyAmount, sellAmount) =>
  baseContext.version === "multiBase" &&
  (buyAmount !== baseContext.config.buyLiquidityRemaining ||
    sellAmount !== baseContext.config.sellLiquidityRemaining);

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
}) =>
  diffSellPrice > toleranceScaled ||
  diffBuyPrice > toleranceScaled ||
  buyPriceWasCappedAtMax ||
  sellPriceWasFlooredAtMin ||
  swapCapsChanged;

module.exports = {
  capDexAmountBySwapLiquidity,
  exceedsMaxBuyPrice,
  fallsBelowMinSellPrice,
  haveSwapCapsChanged,
  resolveDexQuoteAmount,
  shouldUpdatePrices,
};
