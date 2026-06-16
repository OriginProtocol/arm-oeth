const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers, parseUnits } = require("ethers");

const { setOSSiloPrice } = require("../tasks/osSiloPrice");
const { sonic } = require("../utils/addresses");
const erc20Abi = require("../../abis/ERC20.json");
const armAbi = require("../../abis/OriginARM.json");

// Entrypoint for the Defender Action
const handler = async (credentials) => {
  // Initialize defender relayer provider and signer
  const client = new Defender(credentials);
  const provider = client.relaySigner.getProvider({ ethersVersion: "v6" });
  const signer = await client.relaySigner.getSigner(provider, {
    speed: "fastest",
    ethersVersion: "v6",
  });

  const arm = new ethers.Contract(sonic.OriginARM, armAbi, signer);

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
  const wS = new ethers.Contract(sonic.WS, erc20Abi, signer);
  const oS = new ethers.Contract(sonic.OSonicProxy, erc20Abi, signer);

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
    marketPremium: 1, // basis points. Negative value reduces the price
    lendPremium: 200, // basis points added to lending APY (100 = 1%)
    tolerance: 0.3, // basis points
    market: "1inch",
    minSwapAmount: parseUnits("16000", 18),
    minBuyPrice: 0.99,
    // maxBuyPrice: 0.995,
  });
};

module.exports = { handler };
