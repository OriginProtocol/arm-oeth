import { ethers, parseUnits } from "ethers";

import { action } from "../lib/action";
import { setOSSiloPrice } from "../osSiloPrice";

action({
  name: "setPricesSonic",
  description: "Set prices on Sonic ARM",
  chains: [146],
  run: async ({ signer, log }) => {
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
      signer
    );

    // Get the SiloMarketWrapper contract
    const activeMarket = await arm.activeMarket();
    const siloMarketWrapper =
      activeMarket === ethers.ZeroAddress
        ? undefined
        : new ethers.Contract(
            activeMarket,
            ["function market() external view returns (address)"],
            signer
          );

    // Get the WS and OS token contracts
    const wSAddress = await arm.token0();
    const wS = new ethers.Contract(
      wSAddress,
      ["function balanceOf(address) external view returns (uint256)"],
      signer
    );

    const oSAddress = await arm.token1();
    const oS = new ethers.Contract(
      oSAddress,
      ["function balanceOf(address) external view returns (uint256)"],
      signer
    );

    // Get the OS Vault contract
    const vaultAddress = await arm.vault();
    const vault = new ethers.Contract(
      vaultAddress,
      [
        "function withdrawalQueueMetadata() external view returns (uint128,uint128,uint128,uint128)",
        "function withdrawalRequests(uint256) external view returns (address,bool,uint40,uint128,uint128)",
      ],
      signer
    );

    log.info("Setting OS/Silo price on Sonic ARM");
    await setOSSiloPrice({
      signer,
      arm,
      siloMarketWrapper,
      execute: true,
      wS,
      oS,
      vault,
      blockTag: "latest",
      marketPremium: 1,
      lendPremium: 200,
      tolerance: 0.3,
      market: "1inch",
      minSwapAmount: parseUnits("16000", 18),
      minBuyPrice: 0.99,
    });
  },
});
