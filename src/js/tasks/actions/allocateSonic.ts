import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { allocate } from "../admin";
import { sonic } from "../../utils/addresses";
// Sonic still uses the old ARM contract version
const armAbi = require("../../../abis/OriginARMV1.json");

action({
  name: "allocateSonic",
  description: "Allocate liquidity for Origin ARM on Sonic",
  chains: [146],
  params: (t) =>
    t.addOptionalParam(
      "threshold",
      "Liquidity-delta threshold used to skip small allocations, in wS.",
      10000,
      types.float,
    ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(sonic.OriginARM, armAbi, signer);

    log.info("Allocating liquidity for Origin ARM on Sonic");
    await allocate({
      signer,
      arm,
      threshold: args.threshold,
      maxGasPrice: 500,
      armContractVersion: "v1",
    });
  },
});
