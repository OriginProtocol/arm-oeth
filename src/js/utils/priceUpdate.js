const haveSwapCapsChanged = (baseContext, buyAmount, sellAmount) =>
  baseContext.version === "multiBase" &&
  (buyAmount !== baseContext.config.buyLiquidityRemaining ||
    sellAmount !== baseContext.config.sellLiquidityRemaining);

module.exports = {
  haveSwapCapsChanged,
};
