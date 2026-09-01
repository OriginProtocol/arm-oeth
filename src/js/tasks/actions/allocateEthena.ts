import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { allocate } from "../admin";
import { mainnet } from "../../utils/addresses";
const etherFiARMAbi = require("../../../abis/EtherFiARM.json");

action({
  name: "allocateEthena",
  description: "Allocate liquidity for Ethena ARM",
  chains: [1],
  params: (t) =>
    t
      .addOptionalParam(
        "threshold",
        "Liquidity-delta threshold used to skip small allocations, in USDe.",
        30000,
        types.float,
      )
      .addOptionalParam(
        "maxGasPrice",
        "Maximum gas price at which allocation may execute, in gwei.",
        2,
        types.float,
      ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.ethenaARM, etherFiARMAbi, signer);

    log.info("Allocating liquidity for Ethena ARM");
    await allocate({
      signer,
      arm,
      threshold: args.threshold,
      maxGasPrice: args.maxGasPrice,
    });
  },
});
