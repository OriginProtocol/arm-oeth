const assert = require("assert/strict");
const { mkdtempSync, rmSync, writeFileSync } = require("fs");
const { join } = require("path");
const { tmpdir } = require("os");
const test = require("node:test");

const {
  buildAggregatorTargetData,
  deriveVenueMinAmountIn,
  getQuotedAmountIn,
  getRouteAmountOut,
  resolveTokenDirection,
} = require("./marketSwap");

test("resolveTokenDirection maps --from to tokenOut", () => {
  assert.deepEqual(resolveTokenDirection({ arm: "Lido", from: "WETH" }), {
    tokenInSymbol: "stETH",
    tokenOutSymbol: "WETH",
  });
});

test("resolveTokenDirection maps --to to tokenIn", () => {
  assert.deepEqual(resolveTokenDirection({ arm: "Lido", to: "WETH" }), {
    tokenInSymbol: "WETH",
    tokenOutSymbol: "stETH",
  });
});

test("deriveVenueMinAmountIn applies slippage in bps", () => {
  assert.equal(deriveVenueMinAmountIn(10000n, 25), 9975n);
});

test("getQuotedAmountIn supports Kyber and 1inch style routes", () => {
  assert.equal(getQuotedAmountIn({ routeSummary: { amountOut: "123" } }), 123n);
  assert.equal(getQuotedAmountIn({ dstAmount: "456" }), 456n);
});

test("getRouteAmountOut prefers exact-input route fields", () => {
  assert.equal(getRouteAmountOut({ routeSummary: { amountIn: "789" } }), 789n);
  assert.equal(getRouteAmountOut({ srcAmount: "321" }), 321n);
});

test("buildAggregatorTargetData validates amountOut and encodes the swap call", () => {
  const dir = mkdtempSync(join(tmpdir(), "market-swap-task-"));
  const routeFile = join(dir, "route.json");

  writeFileSync(
    routeFile,
    JSON.stringify({
      routeSummary: { amountIn: "100", amountOut: "95" },
      data: "0x1234",
    }),
  );

  const buildResult = buildAggregatorTargetData({
    venue: "kyber",
    tokenInAddress: "0x0000000000000000000000000000000000000001",
    tokenOutAddress: "0x0000000000000000000000000000000000000002",
    routeFile,
    amountOut: 100n,
    slippageBps: 50,
  });

  assert.equal(buildResult.quotedAmountIn, 95n);
  assert.equal(buildResult.minAmountIn, 94n);
  assert.match(buildResult.targetData, /^0x/);

  rmSync(dir, { recursive: true, force: true });
});

test("buildAggregatorTargetData rejects mismatched amountOut", () => {
  const dir = mkdtempSync(join(tmpdir(), "market-swap-task-"));
  const routeFile = join(dir, "route.json");

  writeFileSync(
    routeFile,
    JSON.stringify({
      routeSummary: { amountIn: "101", amountOut: "95" },
      data: "0x1234",
    }),
  );

  assert.throws(
    () =>
      buildAggregatorTargetData({
        venue: "kyber",
        tokenInAddress: "0x0000000000000000000000000000000000000001",
        tokenOutAddress: "0x0000000000000000000000000000000000000002",
        routeFile,
        amountOut: 100n,
        slippageBps: 50,
      }),
    /does not match task amountOut/,
  );

  rmSync(dir, { recursive: true, force: true });
});
