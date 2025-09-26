module.exports = {
  env: {
    es2020: true,
    es6: true,
    node: true,
    amd: true,
    mocha: true,
  },
  extends: "eslint:recommended",
  parserOptions: {
    ecmaVersion: 11,
    sourceType: "module",
  },
  globals: {
    hre: "readable",
    ethers: "readable",
  },
  rules: {
    "no-unexpected-multiline": "off",
  },
  ignorePatterns: ["dist/", "cache_hardhat/", "coverage/"],
};
