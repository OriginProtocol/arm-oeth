const assert = require("assert");

const { parseUnits } = require("ethers");

const {
  MIN_USD_AGGREGATOR_AMOUNT,
  resolveUsdAggregatorAmount,
} = require("../../src/js/utils/usdPricing");

const PYUSD = "0x6c3ea9036406852006290770BEdFcAbA0e23A0e8";

const logger = () => {
  const messages = [];
  return {
    messages,
    info: (message) => messages.push(message),
  };
};

const multiBaseResolver = async () => ({
  version: "multiBase",
  baseAddress: PYUSD,
});

const run = async () => {
  {
    let getReservesCalled = false;
    const amount = await resolveUsdAggregatorAmount({
      amount: 123,
      arm: {
        getReserves: async () => {
          getReservesCalled = true;
          return [parseUnits("456", 6), 0n];
        },
      },
      resolveArmBaseFn: multiBaseResolver,
    });

    assert.strictEqual(amount, 123);
    assert.strictEqual(getReservesCalled, false);
  }

  {
    const log = logger();
    const amount = await resolveUsdAggregatorAmount({
      arm: {
        getReserves: async () => [parseUnits("999.999999", 6), 0n],
      },
      log,
      resolveArmBaseFn: multiBaseResolver,
    });

    assert.strictEqual(amount, "1000.0");
    assert.deepStrictEqual(log.messages, [
      "Using minimum aggregator quote amount of 1000.0 USDC; only 999.999999 USDC is withdrawable in ARM and lending market",
    ]);
  }

  {
    const amount = await resolveUsdAggregatorAmount({
      arm: {
        getReserves: async () => [MIN_USD_AGGREGATOR_AMOUNT, 0n],
      },
      resolveArmBaseFn: multiBaseResolver,
    });

    assert.strictEqual(amount, "1000.0");
  }

  {
    const amount = await resolveUsdAggregatorAmount({
      arm: {
        getReserves: async () => [parseUnits("1654.25", 6), 0n],
      },
      resolveArmBaseFn: multiBaseResolver,
    });

    assert.strictEqual(amount, "1654.25");
  }
};

run()
  .then(() => {
    console.log("usdPricing tests passed");
  })
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
