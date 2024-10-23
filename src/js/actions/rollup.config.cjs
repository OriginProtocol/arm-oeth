const resolve = require("@rollup/plugin-node-resolve");
const commonjs = require("@rollup/plugin-commonjs");
const json = require("@rollup/plugin-json");
const builtins = require("builtin-modules");

const commonConfig = {
  plugins: [
    resolve({ preferBuiltins: true }),
    commonjs(),
    json({ compact: true }),
  ],
  // Do not bundle these packages.
  // ethers is required to be bundled even though it an Autotask package.
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
];
