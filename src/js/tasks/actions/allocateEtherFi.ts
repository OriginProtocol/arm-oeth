import { ethers } from "ethers";

import { action } from "../lib/action";
import { allocate } from "../admin";
import { mainnet } from "../../utils/addresses";
const etherFiARMAbi = require("../../../abis/EtherFiARM.json");

action({
  name: "allocateEtherFi",
  description: "Allocate liquidity for EtherFi ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.etherfiARM, etherFiARMAbi, signer);

    log.info("Allocating liquidity for EtherFi ARM");
    await allocate({
      signer,
      arm,
      threshold: 20,
      maxGasPrice: 5,
    });
  },
});
