const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers } = require("ethers");

const { allocate } = require("../tasks/admin");
const { sonic } = require("../utils/addresses");
const armAbi = require("../../abis/OriginARM.json");

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
  const arm = new ethers.Contract(sonic.OriginARM, armAbi, signer);

  try {
    await allocate({
      signer,
      arm,
    });
  } catch (error) {
    console.error(error);
  }
};

module.exports = { handler };
