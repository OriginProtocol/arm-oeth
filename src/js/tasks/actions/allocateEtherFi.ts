import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { allocate } from "../admin";
import { mainnet } from "../../utils/addresses";
const etherFiARMAbi = require("../../../abis/EtherFiARM.json");

action({
  name: "allocateEtherFi",
  description: "Allocate liquidity for EtherFi ARM",
  chains: [1],
  params: (t) =>
    t.addOptionalParam(
      "threshold",
      "Liquidity-delta threshold used to skip small allocations, in WETH.",
      20,
      types.float,
    ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.etherfiARM, etherFiARMAbi, signer);

    log.info("Allocating liquidity for EtherFi ARM");
    await allocate({
      signer,
      arm,
      threshold: args.threshold,
      maxGasPrice: 5,
    });
  },
});
