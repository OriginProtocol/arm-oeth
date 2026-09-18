const assert = require("assert");
const { parseUnits } = require("ethers");

const {
  computeTranche,
  computeUtilisationBps,
  ladderDiscountBps100,
  ladderMaxBuyPrice,
  parseLadder,
  resolveQuoteAmount,
  scaledInt,
  shouldRefreshBuyCap,
} = require("../../src/js/utils/tranchePricing");

const usde = (amount) => parseUnits(amount.toString(), 18);
const STEP = usde(25000);
const MIN = usde(25000);

// scaledInt
assert.strictEqual(scaledInt("2.5", 100, "bps"), 250);
assert.strictEqual(scaledInt(0.25, 100, "bps"), 25);
assert.strictEqual(scaledInt("0.7", 100, "u"), 70, "float noise is absorbed");
assert.strictEqual(scaledInt(0.25, 10000, "tol"), 2500);
assert.throws(() => scaledInt("2.505", 100, "bps"), /more precision/);
assert.throws(() => scaledInt("abc", 100, "bps"), /Invalid/);
assert.throws(() => scaledInt("", 100, "bps"), /Missing/);

// parseLadder
assert.deepStrictEqual(parseLadder("50:2.5,70:3.5,85:5"), [
  { uBps: 5000, bps100: 250 },
  { uBps: 7000, bps100: 350 },
  { uBps: 8500, bps100: 500 },
]);
assert.deepStrictEqual(
  parseLadder(" 0:3 "),
  [{ uBps: 0, bps100: 300 }],
  "a single knot is a flat ladder",
);
assert.throws(() => parseLadder(""), /Invalid ladder/);
assert.throws(() => parseLadder(undefined), /Invalid ladder/);
assert.throws(() => parseLadder("50:2.5,40:3"), /strictly increasing/);
assert.throws(() => parseLadder("50:2.5,50:3"), /strictly increasing/);
assert.throws(() => parseLadder("150:2.5"), /between 0 and 100/);
assert.throws(() => parseLadder("50:-1"), /must be >= 0/);
assert.throws(() => parseLadder("50"), /expected "u%:bps"/);
assert.throws(() => parseLadder("50:2.5:3"), /expected "u%:bps"/);
assert.throws(() => parseLadder("50:abc"), /Invalid ladder discount/);

// ladderDiscountBps100
const knots = parseLadder("50:2.5,70:3.5,85:5");
assert.strictEqual(
  ladderDiscountBps100(0, knots),
  250,
  "flat below first knot",
);
assert.strictEqual(ladderDiscountBps100(4999, knots), 250);
assert.strictEqual(ladderDiscountBps100(5000, knots), 250, "at knot");
assert.strictEqual(ladderDiscountBps100(6000, knots), 300, "midpoint 50-70");
assert.strictEqual(ladderDiscountBps100(7000, knots), 350, "at knot");
assert.strictEqual(ladderDiscountBps100(7750, knots), 425, "midpoint 70-85");
assert.strictEqual(ladderDiscountBps100(8500, knots), 500, "at knot");
assert.strictEqual(ladderDiscountBps100(10000, knots), 500, "flat above last");
assert.strictEqual(
  ladderDiscountBps100(5100, knots),
  250,
  "just above a knot stays on the notch (nearest, not ceil)",
);
assert.strictEqual(
  ladderDiscountBps100(5250, knots),
  275,
  "ties round up (2.625 -> 2.75)",
);
assert.strictEqual(
  ladderDiscountBps100(5249, knots),
  250,
  "just below the tie rounds down",
);
assert.strictEqual(
  ladderDiscountBps100(6000, knots, 100),
  300,
  "custom step of 1 bps",
);
assert.strictEqual(
  ladderDiscountBps100(5500, knots, 100),
  300,
  "2.75 with a 1 bps step rounds to 3",
);
assert.strictEqual(
  ladderDiscountBps100(6000, parseLadder("0:3")),
  300,
  "single knot is flat everywhere",
);
assert.throws(() => ladderDiscountBps100(0, []), /at least one knot/);
assert.throws(() => ladderDiscountBps100(0, knots, 0), /Invalid ladder step/);

// ladderMaxBuyPrice
assert.strictEqual(ladderMaxBuyPrice(250), parseUnits("0.99975", 36));
assert.strictEqual(ladderMaxBuyPrice(275), parseUnits("0.999725", 36));
assert.strictEqual(ladderMaxBuyPrice(500), parseUnits("0.9995", 36));
assert.strictEqual(ladderMaxBuyPrice(0), parseUnits("1", 36));
const crossPrice = parseUnits("0.99996", 36);
for (let bps100 = 50; bps100 <= 1000; bps100 += 25) {
  assert.ok(
    ladderMaxBuyPrice(bps100) < crossPrice,
    `${bps100 / 100} bps must price below the cross price`,
  );
}

// computeUtilisationBps
assert.strictEqual(computeUtilisationBps(usde(0), usde(100)), 10000);
assert.strictEqual(computeUtilisationBps(usde(100), usde(0)), 10000);
assert.strictEqual(computeUtilisationBps(usde(100), usde(100)), 0);
assert.strictEqual(
  computeUtilisationBps(usde(101), usde(100)),
  0,
  "liquidity above total assets (rounding noise) clamps to 0",
);
assert.strictEqual(computeUtilisationBps(usde(30), usde(100)), 7000);
assert.strictEqual(computeUtilisationBps(usde(30), usde(101)), 7030);

// computeTranche
const tranche = (liquidity, pctBps = 3500) =>
  computeTranche({
    liquidityAssets: usde(liquidity),
    pctBps,
    stepWei: STEP,
    minWei: MIN,
  });
assert.strictEqual(tranche(0), 0n, "no liquidity, no tranche");
assert.strictEqual(tranche(20000), usde(20000), "below min: whole liquidity");
assert.strictEqual(tranche(25000), usde(25000), "at min: whole liquidity");
assert.strictEqual(tranche(50000), usde(25000), "17.5k rounds to 25k");
assert.strictEqual(tranche(200000), usde(75000), "70k rounds to 75k");
assert.strictEqual(tranche(250000), usde(100000), "87.5k ties up to 100k");
assert.strictEqual(tranche(249000), usde(75000), "87.15k rounds down");
assert.strictEqual(tranche(1000000), usde(350000));
assert.strictEqual(tranche(30000, 10000), usde(25000), "100% rounds to 25k");
assert.strictEqual(
  tranche(26000, 10000),
  usde(25000),
  "never above liquidity would be 26k -> rounds to 25k",
);
assert.strictEqual(
  computeTranche({
    liquidityAssets: usde(40000),
    pctBps: 10000,
    stepWei: usde(30000),
    minWei: usde(1000),
  }),
  usde(30000),
  "rounding cannot exceed the liquidity",
);
assert.strictEqual(
  computeTranche({
    liquidityAssets: usde(46000),
    pctBps: 10000,
    stepWei: usde(30000),
    minWei: usde(1000),
  }),
  usde(46000),
  "rounding up above liquidity is clamped to the liquidity",
);
assert.throws(
  () =>
    computeTranche({
      liquidityAssets: usde(100),
      pctBps: 3500,
      stepWei: 0n,
      minWei: MIN,
    }),
  /step must be > 0/,
);
assert.throws(() => tranche(100, 0), /Invalid tranche percentage/);
assert.throws(() => tranche(100, 10001), /Invalid tranche percentage/);

// resolveQuoteAmount
assert.strictEqual(resolveQuoteAmount(0n, usde(1000)), usde(1000));
assert.strictEqual(resolveQuoteAmount(usde(999), usde(1000)), usde(1000));
assert.strictEqual(resolveQuoteAmount(usde(75000), usde(1000)), usde(75000));

// shouldRefreshBuyCap
const refresh = (remaining, target, toleranceBps = 2500) =>
  shouldRefreshBuyCap({
    remaining: usde(remaining),
    target: usde(target),
    toleranceBps,
  });
assert.strictEqual(refresh(100, 100), false, "untouched tranche");
assert.strictEqual(refresh(76, 100), false, "24% consumed");
assert.strictEqual(refresh(75, 100), false, "exactly 25% consumed");
assert.strictEqual(refresh(74, 100), true, "26% consumed");
assert.strictEqual(refresh(101, 100), true, "tranche shrank below remaining");
assert.strictEqual(refresh(0, 0), false, "empty ARM, empty tranche");
assert.strictEqual(refresh(99, 100, 0), true, "zero tolerance is strict");
assert.strictEqual(refresh(100, 100, 0), false);

console.log("tranchePricing tests passed");
