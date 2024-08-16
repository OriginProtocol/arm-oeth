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
];
