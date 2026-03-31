import { ethers } from "ethers";

import { action } from "../lib/action";
import { allocate } from "../admin";
import { mainnet } from "../../utils/addresses";
const lidoARMAbi = require("../../../abis/LidoARM.json");

action({
  name: "allocateLido",
  description: "Allocate liquidity for Lido ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.lidoARM, lidoARMAbi, signer);

    log.info("Allocating liquidity for Lido ARM");
    await allocate({
      signer,
      arm,
      threshold: 200,
      maxGasPrice: 5,
    });
  },
});
