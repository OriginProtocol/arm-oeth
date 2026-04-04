import { ethers } from "ethers";

import { action } from "../lib/action";
import { allocate } from "../admin";
import { mainnet } from "../../utils/addresses";
const armAbi = require("../../../abis/OriginARM.json");

action({
  name: "allocateOETH",
  description: "Allocate liquidity for OETH ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.OethARM, armAbi, signer);

    log.info("Allocating liquidity for OETH ARM");
    await allocate({
      signer,
      arm,
      threshold: 10000,
      maxGasPrice: 500,
    });
  },
});
