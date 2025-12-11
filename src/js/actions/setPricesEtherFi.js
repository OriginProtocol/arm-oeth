const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers } = require("ethers");

const { setPrices } = require("../tasks/lidoMorphoPrices");
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
  const arm = new ethers.Contract(mainnet.etherfiARM, armAbi, signer);

  try {
    await setPrices({
      signer,
      arm,
      // sellPrice: 0.9998,
      // buyPrice: 0.9997,
      maxSellPrice: 1.0,
      minSellPrice: 0.9998,
      maxBuyPrice: 0.9996,
      minBuyPrice: 0.9985,
      // inch: true,
      // curve: true,
      kyber: true,
      amount: 10,
      tolerance: 0.2,
      fee: 0.5,
      offset: 0.3,
      priceOffset: true,
      blockTag: "latest",
    });
  } catch (error) {
    console.error(error);
  }
};

module.exports = { handler };
