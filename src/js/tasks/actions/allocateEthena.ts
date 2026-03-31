import { ethers } from "ethers";

import { action } from "../lib/action";
import { allocate } from "../admin";
import { mainnet } from "../../utils/addresses";
const etherFiARMAbi = require("../../../abis/EtherFiARM.json");

action({
  name: "allocateEthena",
  description: "Allocate liquidity for Ethena ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.ethenaARM, etherFiARMAbi, signer);

    log.info("Allocating liquidity for Ethena ARM");
    await allocate({
      signer,
      arm,
      threshold: 5000,
      maxGasPrice: 5,
    });
  },
});
