const assert = require("assert");

const {
  capDexAmountBySwapLiquidity,
  haveSwapCapsChanged,
  resolveDexQuoteAmount,
} = require("../../src/js/utils/priceUpdate");

const multiBaseContext = (buyLiquidityRemaining, sellLiquidityRemaining) => ({
  version: "multiBase",
  config: {
    buyLiquidityRemaining,
    sellLiquidityRemaining,
  },
});

assert.strictEqual(
  haveSwapCapsChanged(multiBaseContext(10n, 20n), 10n, 20n),
  false,
  "unchanged buy and sell amounts should not trigger an update",
);

assert.strictEqual(
  haveSwapCapsChanged(multiBaseContext(9n, 20n), 10n, 20n),
  true,
  "a changed buy amount should trigger an update",
);

assert.strictEqual(
  haveSwapCapsChanged(multiBaseContext(10n, 19n), 10n, 20n),
  true,
  "a changed sell amount should trigger an update",
);

assert.strictEqual(
  haveSwapCapsChanged({ version: "legacy" }, 10n, 20n),
  false,
  "legacy ARMs do not support buy and sell amounts",
);

assert.strictEqual(
  capDexAmountBySwapLiquidity({
    amount: 100,
    buyLiquidity: 50000000n,
    sellLiquidity: (1n << 128n) - 1n,
    liquidityDecimals: 6,
    baseDecimals: 18,
  }),
  "50.0",
  "buy quote amount should not exceed buy liquidity",
);

assert.strictEqual(
  capDexAmountBySwapLiquidity({
    amount: 100,
    buyLiquidity: (1n << 128n) - 1n,
    sellLiquidity: 25000000000000000000n,
    liquidityDecimals: 6,
    baseDecimals: 18,
  }),
  "25.0",
  "sell quote amount should not exceed sell liquidity",
);

assert.strictEqual(
  capDexAmountBySwapLiquidity({
    amount: 20,
    buyLiquidity: 30000000n,
    sellLiquidity: 10000000000000000000n,
    liquidityDecimals: 6,
    baseDecimals: 18,
  }),
  "10.0",
  "quote amount should use the lower of buy and sell liquidity",
);

assert.strictEqual(
  capDexAmountBySwapLiquidity({
    amount: 20,
    buyLiquidity: 30000000n,
    sellLiquidity: 40000000000000000000n,
    liquidityDecimals: 6,
    baseDecimals: 18,
  }),
  "20",
  "quote amount within both liquidity limits should be unchanged",
);

assert.strictEqual(
  resolveDexQuoteAmount({
    amount: 100,
    liquidityAssets: 50000000n,
    baseAssetReserve: 25000000000000000000n,
    buyLiquidity: 30000000n,
    sellLiquidity: 10000000000000000000n,
    liquidityDecimals: 6,
    baseDecimals: 18,
  }),
  "100",
  "an explicit quote amount should override reserves and price liquidity",
);

assert.strictEqual(
  resolveDexQuoteAmount({
    liquidityAssets: 50000000n,
    baseAssetReserve: 40000000000000000000n,
    buyLiquidity: 30000000n,
    sellLiquidity: 20000000000000000000n,
    liquidityDecimals: 6,
    baseDecimals: 18,
  }),
  "20.0",
  "an automatic quote amount should use the smallest reserve or price liquidity limit",
);

console.log("ARM price tests passed");
