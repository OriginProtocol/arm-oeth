import { ethers } from "ethers";

import { action } from "../lib/action";
import { allocate } from "../admin";
import { mainnet } from "../../utils/addresses";
const multiAssetARMAbi = require("../../../abis/MultiAssetARM.json");

action({
  name: "allocateUSDC",
  description: "Allocate liquidity for USDC ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.usdcARM, multiAssetARMAbi, signer);

    log.info("Allocating liquidity for USDC ARM");
    await allocate({
      signer,
      arm,
      threshold: 500,
      maxGasPrice: 5,
    });
  },
});
