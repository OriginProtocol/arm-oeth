const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers, parseUnits } = require("ethers");

const { setOSSiloPrice } = require("../tasks/osSiloPrice");

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
  const arm = new ethers.Contract(
    armAddress,
    [
      "function traderate0() external view returns (uint256)",
      "function traderate1() external view returns (uint256)",
      "function activeMarket() external view returns (address)",
      "function setPrices(uint256, uint256) external",
      "function vault() external view returns (address)",
      "function token0() external view returns (address)",
      "function token1() external view returns (address)",
      "function withdrawsQueued() external view returns (uint256)",
      "function withdrawsClaimed() external view returns (uint256)",
    ],
    signer,
  );

  // Get the SiloMarketWrapper contract
  const activeMarket = await arm.activeMarket();
  const siloMarketWrapper =
    activeMarket === ethers.ZeroAddress
      ? undefined
      : new ethers.Contract(
          activeMarket,
          ["function market() external view returns (address)"],
          signer,
        );

  // Get the WS and OS token contracts
  const wSAddress = await arm.token0();
  const wS = new ethers.Contract(
    wSAddress,
    ["function balanceOf(address) external view returns (uint256)"],
    signer,
  );

  const oSAddress = await arm.token1();
  const oS = new ethers.Contract(
    oSAddress,
    ["function balanceOf(address) external view returns (uint256)"],
    signer,
  );

  // Get the OS Vault contract
  const vaultAddress = await arm.vault();
  const vault = new ethers.Contract(
    vaultAddress,
    [
      "function withdrawalQueueMetadata() external view returns (uint128,uint128,uint128,uint128)",
      "function withdrawalRequests(uint256) external view returns (address,bool,uint40,uint128,uint128)",
    ],
    signer,
  );

  await setOSSiloPrice({
    signer,
    arm,
    siloMarketWrapper,
    execute: true,
    wS,
    oS,
    vault,
    blockTag: "latest",
    marketPremium: 0.2, // basis points. Negative value reduces the price
    lendPremium: 200, // basis points added to lending APY (100 = 1%)
    tolerance: 0.3, // basis points
    market: "1inch",
    minSwapAmount: parseUnits("1000", 18),
  });
};

module.exports = { handler };
