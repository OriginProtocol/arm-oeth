const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers } = require("ethers");

const { collectRewards } = require("../tasks/sonicHarvest");
const { sonic } = require("../utils/addresses");
const siloMarketAbi = require("../../abis/SiloMarket.json");

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

  // There is only one market for now
  const siloMarket = new ethers.Contract(
    sonic.siloVarlamoreMarket,
    siloMarketAbi,
    signer
  );

  try {
    await collectRewards({
      signer,
      siloMarket,
    });
  } catch (error) {
    console.error(error);
  }
};

module.exports = { handler };
