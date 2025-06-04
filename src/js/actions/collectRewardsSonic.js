const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers } = require("ethers");

const { collectRewards } = require("../tasks/sonicHarvest");
const { sonic } = require("../utils/addresses");
const harvesterAbi = require("../../abis/SonicHarvester.json");

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

  const harvester = new ethers.Contract(sonic.harvester, harvesterAbi, signer);

  try {
    await collectRewards({
      signer,
      harvester,
      strategies: [sonic.siloVarlamoreMarket],
    });
  } catch (error) {
    console.error(error);
  }

  // TODO do Silo, beS and wOS swaps with Magpie
};

module.exports = { handler };
