const log = require("../utils/logger")("utils:block");

// Get the block number
const getBlock = async (block) => {
  const blockTag = !block ? await hre.ethers.provider.getBlockNumber() : block;
  log(`block: ${blockTag}`);

  return blockTag;
};

const getBlockTimestamp = async (blockTag) => {
  const block = await await hre.ethers.provider.getBlock(blockTag);
  const utcDate = new Date(block.timestamp * 1000);

  log(
    `block ${block.number} has timestamp ${
      block.timestamp
    } ${utcDate.toUTCString()}`
  );
  return block.timestamp;
};

const logBlock = async (blockTag) => {
  const block = await getBlock(blockTag);
  const utcDate = new Date(block.timestamp * 1000);
  console.log(`Block: ${block.number}, ${utcDate.toUTCString()}`);
};

module.exports = {
  getBlock,
  getBlockTimestamp,
  logBlock,
};
