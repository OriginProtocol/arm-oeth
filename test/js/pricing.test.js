const assert = require("assert");

const { formatUnits, parseUnits } = require("ethers");

const {
  calculateDynamicPriceOffset,
  calculatePriceOffset,
} = require("../../src/js/utils/pricing");

const prices = ({ sell = "0.9995", buy = "0.9998" } = {}) => ({
  sellPrice: parseUnits(sell, 18),
  buyPrice: parseUnits(buy, 18),
});

const crossPrice = parseUnits("1", 36);
const fullSpreadPrice = 0.999;
const spread = parseUnits("0.0003", 18);

const assertOffset = (actual, expected, label) => {
  assert.strictEqual(formatUnits(actual, 18), expected, label);
};

const run = () => {
  assertOffset(
    calculateDynamicPriceOffset({
      referencePrices: prices({ sell: "1.0", buy: "1.0003" }),
      crossPrice,
      dynamicOffsetFullSpreadPrice: fullSpreadPrice,
    }),
    "0.0",
    "zero at cross price",
  );

  assertOffset(
    calculateDynamicPriceOffset({
      referencePrices: prices({ sell: "0.999", buy: "0.9993" }),
      crossPrice,
      dynamicOffsetFullSpreadPrice: fullSpreadPrice,
    }),
    "0.0003",
    "full spread at anchor",
  );

  assert.strictEqual(
    calculateDynamicPriceOffset({
      referencePrices: prices({ sell: "0.9995", buy: "0.9998" }),
      crossPrice,
      dynamicOffsetFullSpreadPrice: fullSpreadPrice,
    }),
    spread / 2n,
    "half spread halfway between cross and anchor",
  );

  assertOffset(
    calculateDynamicPriceOffset({
      referencePrices: prices({ sell: "0.998", buy: "0.9983" }),
      crossPrice,
      dynamicOffsetFullSpreadPrice: fullSpreadPrice,
    }),
    "0.0003",
    "clamps to full spread below anchor",
  );

  assertOffset(
    calculateDynamicPriceOffset({
      referencePrices: prices({ sell: "1.0001", buy: "1.0004" }),
      crossPrice,
      dynamicOffsetFullSpreadPrice: fullSpreadPrice,
    }),
    "0.0",
    "clamps to zero above cross",
  );

  assert.throws(
    () =>
      calculateDynamicPriceOffset({
        referencePrices: prices(),
        crossPrice,
        dynamicOffsetFullSpreadPrice: 1.0,
      }),
    /must be below cross price/,
  );

  assert.strictEqual(
    calculatePriceOffset({
      offset: 0.2,
      dynamicOffset: false,
      dynamicOffsetFullSpreadPrice: fullSpreadPrice,
      referencePrices: prices(),
      crossPrice,
    }),
    parseUnits("0.2", 14),
    "fixed mode uses configured offset",
  );

  assert.strictEqual(
    calculatePriceOffset({
      offset: 0.2,
      dynamicOffset: true,
      dynamicOffsetFullSpreadPrice: fullSpreadPrice,
      referencePrices: prices({ sell: "0.999", buy: "0.9993" }),
      crossPrice,
    }),
    spread,
    "dynamic mode uses calculated spread offset",
  );
};

run();
console.log("pricing tests passed");
