import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { allocate } from "../admin";
import { mainnet } from "../../utils/addresses";
const multiAssetARMAbi = require("../../../abis/MultiAssetARM.json");

action({
  name: "allocateWETH",
  description: "Allocate liquidity for WETH ARM",
  chains: [1],
  params: (t) =>
    t.addOptionalParam(
      "threshold",
      "Liquidity-delta threshold used to skip small allocations, in WETH.",
      100,
      types.float,
    ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.wethARM, multiAssetARMAbi, signer);

    log.info("Allocating liquidity for WETH ARM");
    await allocate({
      signer,
      arm,
      threshold: args.threshold,
      maxGasPrice: 5,
    });
  },
});
