const assert = require("assert");

const {
  capDexAmountBySwapLiquidity,
  exceedsMaxBuyPrice,
  fallsBelowMinSellPrice,
  haveSwapCapsChanged,
  resolveDexQuoteAmount,
  shouldUpdatePrices,
} = require("../../src/js/utils/priceUpdate");
const { parseSwapCap } = require("../../src/js/utils/arm");
const { parseUnits } = require("ethers");

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

// With a buy cap tolerance, the buy limit is only refreshed once the tranche
// shrank or more than the tolerance was consumed.
const MAX_SWAP_LIQUIDITY = (1n << 128n) - 1n;
const buyCapTolerance = { buyCapToleranceBps: 2500 };

assert.strictEqual(
  haveSwapCapsChanged(multiBaseContext(100n, 20n), 100n, 20n, buyCapTolerance),
  false,
  "unchanged limits with a buyCapTolerance should not trigger an update",
);

assert.strictEqual(
  haveSwapCapsChanged(multiBaseContext(80n, 20n), 100n, 20n, buyCapTolerance),
  false,
  "a buy limit consumed within the buyCapTolerance should not trigger an update",
);

assert.strictEqual(
  haveSwapCapsChanged(multiBaseContext(74n, 20n), 100n, 20n, buyCapTolerance),
  true,
  "a buy limit consumed beyond the buyCapTolerance should trigger an update",
);

assert.strictEqual(
  haveSwapCapsChanged(multiBaseContext(100n, 20n), 90n, 20n, buyCapTolerance),
  true,
  "a tranche smaller than the on-chain buy limit should trigger an update",
);

assert.strictEqual(
  haveSwapCapsChanged(
    multiBaseContext(100n, MAX_SWAP_LIQUIDITY - 5n),
    100n,
    MAX_SWAP_LIQUIDITY,
    buyCapTolerance,
  ),
  false,
  "an uncapped sell limit decremented by swaps should not trigger an update",
);

assert.strictEqual(
  haveSwapCapsChanged(
    multiBaseContext(100n, MAX_SWAP_LIQUIDITY - 5n),
    100n,
    MAX_SWAP_LIQUIDITY,
  ),
  true,
  "without a buyCapTolerance the sell limit comparison stays strict",
);

assert.strictEqual(
  haveSwapCapsChanged(multiBaseContext(100n, 19n), 100n, 20n, buyCapTolerance),
  true,
  "a capped sell limit is still compared strictly",
);

assert.strictEqual(
  haveSwapCapsChanged(
    multiBaseContext(100n, 20n),
    100n,
    MAX_SWAP_LIQUIDITY,
    buyCapTolerance,
  ),
  true,
  "moving a capped sell limit to uncapped should trigger an update",
);

assert.strictEqual(
  haveSwapCapsChanged({ version: "legacy" }, 10n, 20n, buyCapTolerance),
  false,
  "legacy ARMs ignore the buyCapTolerance too",
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

const currentBuyPrice = parseUnits("0.99985", 36);
const cappedBuyPrice = parseUnits("0.99986", 36);
const currentSellPrice = parseUnits("1.00015", 36);
const flooredSellPrice = parseUnits("1.00014", 36);
const capTolerance = parseUnits("0.2", 32);

assert.strictEqual(
  exceedsMaxBuyPrice(parseUnits("0.99991", 36), "0.99986"),
  true,
  "a 0.99991 calculated buy price should be capped at the 0.99986 maximum",
);

assert.strictEqual(
  exceedsMaxBuyPrice(cappedBuyPrice, "0.99986"),
  false,
  "a buy price already at the maximum should not be treated as newly capped",
);

assert.strictEqual(
  shouldUpdatePrices({
    diffSellPrice: 0n,
    diffBuyPrice: cappedBuyPrice - currentBuyPrice,
    toleranceScaled: capTolerance,
    buyPriceWasCappedAtMax: false,
    sellPriceWasFlooredAtMin: false,
    swapCapsChanged: false,
  }),
  false,
  "a 0.1 bps buy-price change should remain below the 0.2 bps capTolerance",
);

assert.strictEqual(
  shouldUpdatePrices({
    diffSellPrice: 0n,
    diffBuyPrice: cappedBuyPrice - currentBuyPrice,
    toleranceScaled: capTolerance,
    buyPriceWasCappedAtMax: true,
    sellPriceWasFlooredAtMin: false,
    swapCapsChanged: false,
  }),
  true,
  "a buy price capped at the maximum should update despite being within capTolerance",
);

assert.strictEqual(
  shouldUpdatePrices({
    diffSellPrice: currentSellPrice - flooredSellPrice,
    diffBuyPrice: 0n,
    toleranceScaled: capTolerance,
    buyPriceWasCappedAtMax: true,
    sellPriceWasFlooredAtMin: false,
    swapCapsChanged: false,
  }),
  false,
  "a capped buy price should not bypass capTolerance for a sell-only price change",
);

assert.strictEqual(
  fallsBelowMinSellPrice(parseUnits("1.0001", 36), "1.00014"),
  true,
  "a 1.0001 calculated sell price should be raised to the 1.00014 minimum",
);

assert.strictEqual(
  fallsBelowMinSellPrice(flooredSellPrice, "1.00014"),
  false,
  "a sell price already at the minimum should not be treated as newly floored",
);

assert.strictEqual(
  shouldUpdatePrices({
    diffSellPrice: currentSellPrice - flooredSellPrice,
    diffBuyPrice: 0n,
    toleranceScaled: capTolerance,
    buyPriceWasCappedAtMax: false,
    sellPriceWasFlooredAtMin: false,
    swapCapsChanged: false,
  }),
  false,
  "a 0.1 bps sell-price change should remain below the 0.2 bps capTolerance",
);

assert.strictEqual(
  shouldUpdatePrices({
    diffSellPrice: currentSellPrice - flooredSellPrice,
    diffBuyPrice: 0n,
    toleranceScaled: capTolerance,
    buyPriceWasCappedAtMax: false,
    sellPriceWasFlooredAtMin: true,
    swapCapsChanged: false,
  }),
  true,
  "a sell price raised to the minimum should update despite being within capTolerance",
);

assert.strictEqual(
  shouldUpdatePrices({
    diffSellPrice: 0n,
    diffBuyPrice: cappedBuyPrice - currentBuyPrice,
    toleranceScaled: capTolerance,
    buyPriceWasCappedAtMax: false,
    sellPriceWasFlooredAtMin: true,
    swapCapsChanged: false,
  }),
  false,
  "a floored sell price should not bypass capTolerance for a buy-only price change",
);

assert.strictEqual(
  shouldUpdatePrices({
    diffSellPrice: 0n,
    diffBuyPrice: 0n,
    toleranceScaled: capTolerance,
    buyPriceWasCappedAtMax: true,
    sellPriceWasFlooredAtMin: true,
    swapCapsChanged: false,
  }),
  false,
  "prices already at their configured bounds should not trigger a no-op update",
);

assert.strictEqual(
  shouldUpdatePrices({
    diffSellPrice: 0n,
    diffBuyPrice: 0n,
    toleranceScaled: capTolerance,
    buyPriceWasCappedAtMax: true,
    sellPriceWasFlooredAtMin: false,
    swapCapsChanged: true,
  }),
  true,
  "changed swap caps should still update when bounded prices are unchanged",
);

console.log("ARM price tests passed");
