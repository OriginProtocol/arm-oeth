const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers } = require("ethers");

const { claimEtherFiWithdrawals } = require("../tasks/etherfiQueue");
const { mainnet } = require("../utils/addresses");
const etherFiWithdrawalQueueAbi = require("../../abis/EtherFiWithdrawQueue.json");
const etherFiARMAbi = require("../../abis/EtherFiARM.json");

// Entrypoint for the Defender Action
const handler = async (event) => {
  // Initialize defender relayer provider and signer
  const client = new Defender(event);
  const provider = client.relaySigner.getProvider({ ethersVersion: "v6" });
  const signer = await client.relaySigner.getSigner(provider, {
    speed: "fastest",
    ethersVersion: "v6",
  });

  console.log(
    `DEBUG env var in handler before being set: "${process.env.DEBUG}"`,
  );

  // References to contracts
  const arm = new ethers.Contract(mainnet.etherfiARM, etherFiARMAbi, signer);
  const withdrawalQueue = new ethers.Contract(
    mainnet.etherfiWithdrawalQueue,
    etherFiWithdrawalQueueAbi,
    signer,
  );

  await claimEtherFiWithdrawals({
    signer,
    arm,
    withdrawalQueue,
  });
};

module.exports = { handler };
