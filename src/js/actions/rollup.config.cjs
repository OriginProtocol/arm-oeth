const resolve = require("@rollup/plugin-node-resolve");
const commonjs = require("@rollup/plugin-commonjs");
const json = require("@rollup/plugin-json");
const builtins = require("builtin-modules");
const { visualizer } = require("rollup-plugin-visualizer");

const commonConfig = {
  plugins: [
    resolve({ preferBuiltins: true }),
    commonjs(),
    json({ compact: true }),
    // Generates a stats.html file in the actions folder.
    // This is a visual of the Action dependencies for the last Action in the rollup config.
    visualizer(),
  ],
  // Do not bundle these packages.
  // ethers is required to be bundled as we need v6 and not v5 that is packaged with Defender Actions.
  external: [
    ...builtins,
    "axios",
    "chai",
    /^defender-relay-client(\/.*)?$/,
    "@openzeppelin/defender-relay-client/lib/ethers",
    "@openzeppelin/defender-sdk",
    "@openzeppelin/defender-autotask-client",
    "@openzeppelin/defender-kvstore-client",
    "@openzeppelin/defender-relay-client/lib/ethers",
    "@nomicfoundation/solidity-analyzer-darwin-arm64",
    "@nomicfoundation/solidity-analyzer-darwin-x64",
    "fsevents",
  ],
};

module.exports = [
  {
    input: "autoRequestWithdraw.js",
    output: {
      file: "dist/autoRequestWithdraw/index.js",
      format: "cjs",
    },
    ...commonConfig,
  },
  {
    input: "autoClaimWithdraw.js",
    output: {
      file: "dist/autoClaimWithdraw/index.js",
      format: "cjs",
    },
    ...commonConfig,
  },
  {
    input: "autoRequestLidoWithdraw.js",
    output: {
      file: "dist/autoRequestLidoWithdraw/index.js",
      format: "cjs",
    },
    ...commonConfig,
  },
  {
    input: "autoClaimLidoWithdraw.js",
    output: {
      file: "dist/autoClaimLidoWithdraw/index.js",
      format: "cjs",
    },
    ...commonConfig,
  },
  {
    input: "collectLidoFees.js",
    output: {
      file: "dist/collectLidoFees/index.js",
      format: "cjs",
    },
    ...commonConfig,
  },
  {
    input: "setPrices.js",
    output: {
      file: "dist/setPrices/index.js",
      format: "cjs",
    },
    ...commonConfig,
  },
];
