const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers } = require("ethers");

const { claimLidoWithdrawals } = require("../tasks/lidoQueue");
const { mainnet } = require("../utils/addresses");
const lidoWithdrawalQueueAbi = require("../../abis/LidoWithdrawQueue.json");
const lidoARMAbi = require("../../abis/LidoARM.json");

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
    `DEBUG env var in handler before being set: "${process.env.DEBUG}"`
  );

  // References to contracts
  const arm = new ethers.Contract(mainnet.lidoARM, lidoARMAbi, signer);
  const withdrawalQueue = new ethers.Contract(
    mainnet.lidoWithdrawalQueue,
    lidoWithdrawalQueueAbi,
    signer
  );

  await claimLidoWithdrawals({
    signer,
    arm,
    withdrawalQueue,
  });
};

module.exports = { handler };
