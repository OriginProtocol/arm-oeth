import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { allocate } from "../admin";
import { mainnet } from "../../utils/addresses";
const armAbi = require("../../../abis/OriginARM.json");

action({
  name: "allocateOETH",
  description: "Allocate liquidity for OETH ARM",
  chains: [1],
  params: (t) =>
    t.addOptionalParam(
      "threshold",
      "Liquidity-delta threshold used to skip small allocations, in WETH.",
      100,
      types.float,
    ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.OethARM, armAbi, signer);

    log.info("Allocating liquidity for OETH ARM");
    await allocate({
      signer,
      arm,
      threshold: args.threshold,
      maxGasPrice: 500,
    });
  },
});
