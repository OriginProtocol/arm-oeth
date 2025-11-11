const { ethers } = require("ethers");
const { mainnet } = require("./addresses");
const { getSigner } = require("./signers");

const log = require("../utils/logger")("utils:Ether.fi");

const logWithdrawalRequests = async ({ blockTag }) => {
  const signer = await getSigner();
  // Get list of withdrawal NFTs owned by the Ether.fi ARM contract

  log(
    `About to get last finalized withdrawal request ID from ${mainnet.etherfiWithdrawalQueue}`,
  );

  const withdrawalNFT = new ethers.Contract(
    mainnet.etherfiWithdrawalQueue,
    ["function lastFinalizedRequestId() view returns (uint32)"],
    signer,
  );

  const lastFinalizedRequestId = await withdrawalNFT.lastFinalizedRequestId({
    blockTag,
  });
  console.log(
    `Last finalized withdrawal request ID: ${lastFinalizedRequestId}`,
  );
};

module.exports = { logWithdrawalRequests };
