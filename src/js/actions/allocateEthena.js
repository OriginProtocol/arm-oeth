const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers } = require("ethers");

const { allocate } = require("../tasks/admin");
const { mainnet } = require("../utils/addresses");
const armAbi = require("../../abis/EtherFiARM.json");

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
  const arm = new ethers.Contract(mainnet.ethenaARM, armAbi, signer);
  const armConfig = {
    // Pre-upgrade default: omit armContractVersion so allocation auto-detects.
    // Post-upgrade: keep omitted, or temporarily pin "v2" while rolling out.
    // armContractVersion: "v2",
  };

  await allocate({
    signer,
    arm,
    ...armConfig,
    threshold: 5000,
    maxGasPrice: 5,
  });
};

module.exports = { handler };
