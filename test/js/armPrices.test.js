const assert = require("assert");

const {
  capDexAmountBySwapLiquidity,
  haveSwapCapsChanged,
  resolveDexQuoteAmount,
} = require("../../src/js/utils/priceUpdate");
const { parseSwapCap } = require("../../src/js/utils/arm");

assert.strictEqual(
  parseSwapCap("1", 18),
  10n ** 18n,
  "one 18-decimal token should not be parsed as one wei",
);

assert.strictEqual(
  parseSwapCap("1", 6),
  10n ** 6n,
  "one 6-decimal token should use the token's native decimals",
);

assert.strictEqual(
  parseSwapCap("1.5", 6),
  1_500_000n,
  "fractional token amounts should be supported",
);

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
