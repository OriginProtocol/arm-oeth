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

module.exports = {
  capDexAmountBySwapLiquidity,
  haveSwapCapsChanged,
  resolveDexQuoteAmount,
};
