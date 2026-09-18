const assert = require("assert");

const { formatUnits, parseUnits } = require("ethers");

const {
  MIN_ETHENA_AGGREGATOR_AMOUNT,
  resolveEthenaTranche,
} = require("../../src/js/utils/ethenaPricing");

const sUSDe = "0x9D39A5DE30e57443BfF2A8307A4256c8797A3497";
const adapterAddress = "0xe620AfB67223AE03C260112AE21A717Af94C90F0";
const usde = (amount) => parseUnits(amount.toString(), 18);
const NAV = parseUnits("1.24", 18);

const defaults = {
  tranchePctBps: 3500,
  trancheStepWei: usde(25000),
  trancheMinWei: usde(25000),
  ladder: "50:2.5,70:3.5,85:5",
  ladderStepBps100: 25,
};

const makeArm = ({ liquidity, total, calls = {} }) => ({
  runner: "runner",
  getReserves: async (baseAddress, overrides) => {
    calls.getReserves = { baseAddress, overrides };
    return [liquidity, 0n];
  },
  totalAssets: async (overrides) => {
    calls.totalAssets = { overrides };
    return total;
  },
});

const resolver = async ({ blockTag }) => ({
  version: "multiBase",
  baseAddress: sUSDe,
  liquidityAddress: "0x4c9EDD5852cd905f086C759E8383e09bff1E68B3",
  config: {
    adapter: adapterAddress,
    baseAssetDecimals: 18,
    crossPrice: parseUnits("0.99996", 36),
    buyLiquidityRemaining: 0n,
  },
  blockTag,
});

const adapterFactory =
  (calls = {}) =>
  async (address, runner) => {
    calls.adapter = { address, runner };
    return {
      convertToShares: async (assets, overrides) => {
        calls.convertToShares = { assets, overrides };
        return (assets * parseUnits("1", 18)) / NAV;
      },
    };
  };

const run = async () => {
  {
    // 200k liquid of 1M total: u = 80%, ladder 4.5 bps, tranche 75k
    const calls = {};
    const result = await resolveEthenaTranche({
      arm: makeArm({ liquidity: usde(200000), total: usde(1000000), calls }),
      blockTag: 123,
      maxBuyPrice: 0.99985,
      resolveArmBaseFn: resolver,
      adapterContractFn: adapterFactory(calls),
      ...defaults,
    });

    assert.strictEqual(result.utilisationBps, 8000);
    assert.strictEqual(result.ladderBps100, 450);
    assert.strictEqual(result.buyAmount, usde(75000));
    assert.strictEqual(typeof result.buyAmount, "bigint");
    assert.strictEqual(result.maxBuyPrice, "0.99955");
    assert.strictEqual(
      parseUnits(result.maxBuyPrice, 36),
      parseUnits("0.99955", 36),
      "max buy price round-trips exactly through parseUnits",
    );
    assert.strictEqual(
      result.amount,
      formatUnits((usde(75000) * parseUnits("1", 18)) / NAV, 18),
      "quote size is the tranche converted to sUSDe shares",
    );
    assert.strictEqual(calls.getReserves.baseAddress, sUSDe);
    assert.deepStrictEqual(calls.getReserves.overrides, { blockTag: 123 });
    assert.deepStrictEqual(calls.totalAssets.overrides, { blockTag: 123 });
    assert.deepStrictEqual(calls.convertToShares.overrides, { blockTag: 123 });
    assert.strictEqual(calls.convertToShares.assets, usde(75000));
    assert.deepStrictEqual(calls.adapter, {
      address: adapterAddress,
      runner: "runner",
    });
  }

  {
    // idle ARM: u = 0, ladder floor 2.5 bps, tranche 35% of 1M = 350k
    const result = await resolveEthenaTranche({
      arm: makeArm({ liquidity: usde(1000000), total: usde(1000000) }),
      maxBuyPrice: 0.99985,
      resolveArmBaseFn: resolver,
      adapterContractFn: adapterFactory(),
      ...defaults,
    });
    assert.strictEqual(result.utilisationBps, 0);
    assert.strictEqual(result.maxBuyPrice, "0.99975");
    assert.strictEqual(result.buyAmount, usde(350000));
  }

  {
    // a guard tighter than the ladder wins
    const result = await resolveEthenaTranche({
      arm: makeArm({ liquidity: usde(1000000), total: usde(1000000) }),
      maxBuyPrice: 0.9997,
      resolveArmBaseFn: resolver,
      adapterContractFn: adapterFactory(),
      ...defaults,
    });
    assert.strictEqual(result.maxBuyPrice, "0.9997");
  }

  {
    // no guard: the ladder alone
    const result = await resolveEthenaTranche({
      arm: makeArm({ liquidity: usde(1000000), total: usde(1000000) }),
      resolveArmBaseFn: resolver,
      adapterContractFn: adapterFactory(),
      ...defaults,
    });
    assert.strictEqual(result.maxBuyPrice, "0.99975");
  }

  {
    // nearly empty ARM: tranche is the whole 5k, quote floored at 1,000 USDe
    const calls = {};
    const result = await resolveEthenaTranche({
      arm: makeArm({ liquidity: usde(500), total: usde(1000000), calls }),
      resolveArmBaseFn: resolver,
      adapterContractFn: adapterFactory(calls),
      ...defaults,
    });
    assert.strictEqual(result.utilisationBps, 9995);
    assert.strictEqual(result.ladderBps100, 500);
    assert.strictEqual(result.buyAmount, usde(500));
    assert.strictEqual(
      calls.convertToShares.assets,
      MIN_ETHENA_AGGREGATOR_AMOUNT,
    );
  }

  {
    // empty ARM: zero tranche, quote still floored
    const calls = {};
    const result = await resolveEthenaTranche({
      arm: makeArm({ liquidity: 0n, total: usde(1000000), calls }),
      resolveArmBaseFn: resolver,
      adapterContractFn: adapterFactory(calls),
      ...defaults,
    });
    assert.strictEqual(result.buyAmount, 0n);
    assert.strictEqual(
      calls.convertToShares.assets,
      MIN_ETHENA_AGGREGATOR_AMOUNT,
    );
  }

  {
    // named reserve tuple fields are supported
    const result = await resolveEthenaTranche({
      arm: {
        runner: "runner",
        getReserves: async () => ({
          liquidityAssets: usde(400000),
          baseAssetReserve: 0n,
        }),
        totalAssets: async () => usde(1000000),
      },
      resolveArmBaseFn: resolver,
      adapterContractFn: adapterFactory(),
      ...defaults,
    });
    assert.strictEqual(result.utilisationBps, 6000);
    assert.strictEqual(result.ladderBps100, 300);
    assert.strictEqual(result.buyAmount, usde(150000));
  }

  {
    // legacy ARM is rejected
    await assert.rejects(
      resolveEthenaTranche({
        arm: makeArm({ liquidity: usde(1), total: usde(1) }),
        resolveArmBaseFn: async () => ({ version: "legacy" }),
        adapterContractFn: adapterFactory(),
        ...defaults,
      }),
      /requires a multi-base/,
    );
  }

  {
    // a bad ladder fails before any chain read
    let read = false;
    await assert.rejects(
      resolveEthenaTranche({
        arm: {
          getReserves: async () => {
            read = true;
            return [0n, 0n];
          },
          totalAssets: async () => 0n,
        },
        resolveArmBaseFn: resolver,
        adapterContractFn: adapterFactory(),
        ...defaults,
        ladder: "70:3.5,50:2.5",
      }),
      /strictly increasing/,
    );
    assert.strictEqual(read, false);
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
