const path = require("path");
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
    "node-fetch",
    /^defender-relay-client(\/.*)?$/,
    "@openzeppelin/defender-relay-client/lib/ethers",
    "@openzeppelin/defender-sdk",
    "@openzeppelin/defender-autotask-client",
    "@openzeppelin/defender-kvstore-client",
    "@openzeppelin/defender-relay-client/lib/ethers",
    "@nomicfoundation/solidity-analyzer-darwin-arm64",
    "@nomicfoundation/solidity-analyzer-darwin-x64",
    /^@nomicfoundation\/edr-.*$/,
    "fsevents",
  ],
};

const actions = [
  "autoRequestWithdraw",
  "autoClaimWithdraw",
  "autoRequestWithdrawSonic",
  "autoClaimWithdrawSonic",
  "autoRequestLidoWithdraw",
  "autoClaimLidoWithdraw",
  "autoRequestEtherFiWithdraw",
  "autoClaimEtherFiWithdraw",
  "autoRequestEthenaWithdraw",
  "autoClaimEthenaWithdraw",
  "collectLidoFees",
  "collectFeesSonic",
  "collectEtherFiFees",
  "collectEthenaFees",
  "collectOETHFees",
  "collectRewardsSonic",
  "allocateLido",
  "allocateEtherFi",
  "allocateEthena",
  "allocateOETH",
  "allocateSonic",
  "setOSSiloPriceAction",
  "setPrices",
  "setPricesEtherFi",
  "setPricesOETH",
];

module.exports = actions.map((action) => ({
  input: path.resolve(__dirname, `${action}.js`),
  output: {
    file: path.resolve(__dirname, `dist/${action}/index.js`),
    format: "cjs",
  },
  ...commonConfig,
}));
