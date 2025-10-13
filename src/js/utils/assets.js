const { ethereumAddress } = require("./regex");
const { parseAddress } = require("./addressParser");
// Commented out as Hardhat will load a version of ethers with helper function getContractAt
// which comes from the @nomicfoundation/hardhat-ethers package.
// The following needs to be uncommented if building for an Autotask
// const { ethers } = require("ethers");

const log = require("../utils/logger")("utils:assets");

/**
 * Resolves a token symbol to a ERC20 token contract.
 * @param {string} symbol token symbol of the asset. eg OUSD, USDT, stETH, CRV...
 */
const resolveAddress = async (symbol) => {
  if (symbol.match(ethereumAddress)) return symbol;

  const assetAddr = await parseAddress(symbol);
  if (!assetAddr) {
    throw Error(`Failed to resolve symbol "${symbol}" to an address`);
  }
  log(`Resolved ${symbol} to ${assetAddr}`);
  return assetAddr;
};

/**
 * Resolves a token symbol to a ERC20 token contract.
 * @param {string} symbol token symbol of the asset. eg OUSD, USDT, stETH, CRV...
 */
const resolveAsset = async (symbol) => {
  const assetAddr = await parseAddress(symbol);
  if (!assetAddr) {
    throw Error(`Failed to resolve symbol "${symbol}" to an address`);
  }
  log(`Resolved ${symbol} to ${assetAddr}`);
  const asset = await ethers.getContractAt("IERC20Metadata", assetAddr);
  return asset;
};

module.exports = {
  resolveAddress,
  resolveAsset,
};
