const { Defender } = require("@openzeppelin/defender-sdk");
const { setOSSiloPrice } = require("../tasks/osSiloPrice");
const { ethers } = require("ethers");

// Entrypoint for the Defender Action
const handler = async (credentials) => {
  // Initialize defender relayer provider and signer
  const client = new Defender(credentials);
  const provider = client.relaySigner.getProvider({ ethersVersion: "v6" });
  const signer = await client.relaySigner.getSigner(provider, {
    speed: "fastest",
    ethersVersion: "v6",
  });

  const armAddress = "0x2F872623d1E1Af5835b08b0E49aAd2d81d649D30";
  const arm = new ethers.Contract(armAddress, [
    "function traderate0() external view returns (uint256)",
    "function traderate1() external view returns (uint256)",
    "function activeMarket() external view returns (address)",
    "function setPrices(uint256, uint256) external",
  ], signer);

  const activeMarket = await arm.activeMarket();
  if (activeMarket === ethers.ZeroAddress) {
    log("No active lending market found, using default APY of 0%");
    return 0n;
  }

  // Get the SiloMarketWrapper contract
  const siloMarketWrapper = new ethers.Contract(activeMarket, [
    "function market() external view returns (address)",
  ], signer);

    await setOSSiloPrice({
      signer,
      arm,
      siloMarketWrapper,
      execute: true,
    });
};

module.exports = { handler };
