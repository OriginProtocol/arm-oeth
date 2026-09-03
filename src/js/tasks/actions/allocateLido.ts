import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { allocate } from "../admin";
import { mainnet } from "../../utils/addresses";
const lidoARMAbi = require("../../../abis/LidoARM.json");

action({
  name: "allocateLido",
  description: "Allocate liquidity for Lido ARM",
  chains: [1],
  params: (t) =>
    t
      .addOptionalParam(
        "threshold",
        "Liquidity-delta threshold used to skip small allocations, in WETH.",
        100,
        types.float,
      )
      .addOptionalParam(
        "maxGasPrice",
        "Maximum gas price at which allocation may execute, in gwei.",
        2,
        types.float,
      ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.lidoARM, lidoARMAbi, signer);

    log.info("Allocating liquidity for Lido ARM");
    await allocate({
      signer,
      arm,
      threshold: args.threshold,
      maxGasPrice: args.maxGasPrice,
    });
  },
});
