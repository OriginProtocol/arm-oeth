import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { allocate } from "../admin";
import { mainnet } from "../../utils/addresses";
const multiAssetARMAbi = require("../../../abis/MultiAssetARM.json");

action({
  name: "allocateUSDC",
  description: "Allocate liquidity for USDC ARM",
  chains: [1],
  params: (t) =>
    t
      .addOptionalParam(
        "threshold",
        "Liquidity-delta threshold used to skip small allocations, in USDC.",
        15000,
        types.float,
      )
      .addOptionalParam(
        "maxGasPrice",
        "Maximum gas price at which allocation may execute, in gwei.",
        2,
        types.float,
      ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.usdcARM, multiAssetARMAbi, signer);

    log.info("Allocating liquidity for USDC ARM");
    await allocate({
      signer,
      arm,
      threshold: args.threshold,
      maxGasPrice: args.maxGasPrice,
    });
  },
});
