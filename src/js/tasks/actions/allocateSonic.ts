import { ethers } from "ethers";

import { action } from "../lib/action";
import { allocate } from "../admin";
import { sonic } from "../../utils/addresses";
const armAbi = require("../../../abis/OriginARM.json");

action({
  name: "allocateSonic",
  description: "Allocate liquidity for Origin ARM on Sonic",
  chains: [146],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(sonic.OriginARM, armAbi, signer);

    log.info("Allocating liquidity for Origin ARM on Sonic");
    await allocate({
      signer,
      arm,
      threshold: 10000,
      maxGasPrice: 500,
      armContractVersion: "v1",
    });
  },
});
