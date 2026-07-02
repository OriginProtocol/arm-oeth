const assert = require("assert");

const { parseUnits } = require("ethers");

const {
  DEFAULT_ETHENA_AGGREGATOR_AMOUNT,
  resolveEthenaAggregatorAmount,
} = require("../../src/js/utils/ethenaPricing");

const sUSDe = "0x9D39A5DE30e57443BfF2A8307A4256c8797A3497";

const logger = () => {
  const messages = [];
  return {
    messages,
    info: (message) => messages.push(message),
  };
};

const multiBaseResolver = async () => ({
  version: "multiBase",
  baseAddress: sUSDe,
});

const legacyResolver = async () => ({
  version: "legacy",
  baseAddress: sUSDe,
});

const run = async () => {
  {
    let getReservesCalled = false;
    const log = logger();
    const amount = await resolveEthenaAggregatorAmount({
      amount: 123,
      log,
      arm: {
        getReserves: async () => {
          getReservesCalled = true;
          return [parseUnits("456", 18), 0n];
        },
      },
      resolveArmBaseFn: multiBaseResolver,
    });

    assert.strictEqual(amount, 123);
    assert.strictEqual(getReservesCalled, false);
    assert.deepStrictEqual(log.messages, [
      "Using configured aggregator quote amount: 123 USDe",
    ]);
  }

  {
    let requestedBaseAddress;
    const amount = await resolveEthenaAggregatorAmount({
      arm: {
        getReserves: async (baseAddress) => {
          requestedBaseAddress = baseAddress;
          return [parseUnits("789.123", 18), 0n];
        },
      },
      resolveArmBaseFn: multiBaseResolver,
    });

    assert.strictEqual(requestedBaseAddress, sUSDe);
    assert.strictEqual(amount, "789.123");
  }

  {
    const amount = await resolveEthenaAggregatorAmount({
      arm: {
        getReserves: async () => ({
          liquidityAssets: parseUnits("321", 18),
          baseAssetReserve: 0n,
        }),
      },
      resolveArmBaseFn: multiBaseResolver,
    });

    assert.strictEqual(amount, "321.0");
  }

  {
    const log = logger();
    const amount = await resolveEthenaAggregatorAmount({
      arm: {
        getReserves: async () => [0n, 0n],
      },
      log,
      resolveArmBaseFn: multiBaseResolver,
    });

    assert.strictEqual(amount, undefined);
    assert.deepStrictEqual(log.messages, [
      "Skipping Ethena price update: no withdrawable USDe available in ARM or lending market",
    ]);
  }

  {
    let getReservesCalled = false;
    const amount = await resolveEthenaAggregatorAmount({
      arm: {
        getReserves: async () => {
          getReservesCalled = true;
          return [parseUnits("456", 18), 0n];
        },
      },
      resolveArmBaseFn: legacyResolver,
    });

    assert.strictEqual(amount, DEFAULT_ETHENA_AGGREGATOR_AMOUNT);
    assert.strictEqual(getReservesCalled, false);
  }

  {
    let commonPricingAmount;
    const resolvedAmount = await resolveEthenaAggregatorAmount({
      arm: {
        getReserves: async () => [parseUnits("654", 18), 0n],
      },
      resolveArmBaseFn: multiBaseResolver,
    });

    const setPricesForBases = async ({ options }) => {
      commonPricingAmount = options.amount;
    };
    await setPricesForBases({
      options: {
        amount: resolvedAmount,
        kyber: true,
        inch: true,
      },
    });

    assert.strictEqual(commonPricingAmount, "654.0");
  }
};

run()
  .then(() => {
    console.log("ethenaPricing tests passed");
  })
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
