import { ethers } from "ethers";

import { action } from "../lib/action";
import { allocate } from "../admin";
import { mainnet } from "../../utils/addresses";
const multiAssetARMAbi = require("../../../abis/MultiAssetARM.json");

action({
  name: "allocateWETH",
  description: "Allocate liquidity for WETH ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.wethARM, multiAssetARMAbi, signer);

    log.info("Allocating liquidity for WETH ARM");
    await allocate({
      signer,
      arm,
      threshold: 100,
      maxGasPrice: 5,
    });
  },
});
