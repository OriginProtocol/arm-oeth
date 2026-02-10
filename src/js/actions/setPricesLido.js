const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers } = require("ethers");

const { setPrices } = require("../tasks/armPrices");
const { mainnet } = require("../utils/addresses");
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
    `DEBUG env var in handler before being set: "${process.env.DEBUG}"`,
  );

  // References to contracts
  const arm = new ethers.Contract(mainnet.lidoARM, lidoARMAbi, signer);

  try {
    await setPrices({
      signer,
      arm,
      // sellPrice: 0.9998,
      // buyPrice: 0.9997,
      maxSellPrice: 1.0,
      minSellPrice: 0.9999,
      maxBuyPrice: 0.999,
      minBuyPrice: 0.998,
      // inch: true,
      // curve: true,
      kyber: true,
      amount: 100,
      tolerance: 0.1,
      fee: 0.5,
      offset: 0.1,
      priceOffset: true,
      blockTag: "latest",
    });
  } catch (error) {
    console.error(error);
  }
};

module.exports = { handler };
