const assert = require("assert");

const {
  orderPendingUnstakerStates,
  selectClaimableFifoPrefix,
} = require("../../src/js/utils/ethenaQueue");

const state = (index, isReady = false) => ({
  index,
  shares: BigInt(index + 1),
  isReady,
});

const run = async () => {
  {
    const states = [state(39, true), state(40, false)];
    const ordered = orderPendingUnstakerStates(states, 41n, 42n);

    assert.deepStrictEqual(
      ordered.map(({ index }) => index),
      [39, 40],
    );
    assert.deepStrictEqual(
      selectClaimableFifoPrefix(ordered).map(({ index }) => index),
      [39],
    );
  }

  {
    // Requests 41-44 are pending after the first rotation. Reading the current
    // slots by index returns 0, 1, 2 before 41, but the FIFO starts at 41.
    const states = [
      state(0, false),
      state(1, false),
      state(2, false),
      state(41, true),
    ];
    const ordered = orderPendingUnstakerStates(states, 45n, 42n);

    assert.deepStrictEqual(
      ordered.map(({ index }) => index),
      [41, 0, 1, 2],
    );
    assert.deepStrictEqual(
      selectClaimableFifoPrefix(ordered).map(({ index }) => index),
      [41],
    );
  }

  {
    const states = [state(0, true), state(1, true), state(2, true)];
    const ordered = orderPendingUnstakerStates(states, 45n, 42n);

    assert.strictEqual(ordered.length, 3);
    assert.strictEqual(
      ordered.reduce((shares, item) => shares + item.shares, 0n),
      6n,
    );
  }

  {
    assert.throws(
      () => orderPendingUnstakerStates([state(0)], 45n, 42n),
      /Missing Ethena unstaker 2 for pending request 44/,
    );
  }
};

run()
  .then(() => console.log("ethenaQueue tests passed"))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
