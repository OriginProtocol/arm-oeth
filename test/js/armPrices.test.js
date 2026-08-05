const assert = require("assert");

const { haveSwapCapsChanged } = require("../../src/js/utils/priceUpdate");
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

console.log("ARM price tests passed");
