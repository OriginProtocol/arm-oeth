const log = require("../utils/logger")("task:block");

// Get the block details like number and timestamp
const getBlock = async (block) => {
  const blockDetails = await hre.ethers.provider.getBlock(block);
  log(`block: ${blockDetails.number}`);

  return blockDetails;
};

const logBlock = async (blockTag) => {
  const block = await getBlock(blockTag);
  const utcDate = new Date(block.timestamp * 1000);
  console.log(`Block: ${block.number}, ${utcDate.toUTCString()}`);
};

module.exports = {
  getBlock,
  logBlock,
};
