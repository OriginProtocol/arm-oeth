import { ethers } from "ethers";

import { action } from "../lib/action";
import { allocate } from "../admin";
import { mainnet } from "../../utils/addresses";
const multiAssetARMAbi = require("../../../abis/MultiAssetARM.json");

action({
  name: "allocateUSD",
  description: "Allocate liquidity for USD ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.usdARM, multiAssetARMAbi, signer);

    log.info("Allocating liquidity for USD ARM");
    await allocate({
      signer,
      arm,
      threshold: 500,
      maxGasPrice: 5,
      decimals: 6,
    });
  },
});
