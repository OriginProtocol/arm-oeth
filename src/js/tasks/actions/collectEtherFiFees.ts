import { ethers } from "ethers";

import { action } from "../lib/action";
import { collectFees } from "../admin";
import { mainnet } from "../../utils/addresses";
const etherFiARMAbi = require("../../../abis/EtherFiARM.json");

action({
  name: "collectEtherFiFees",
  description: "Collect fees from EtherFi ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.etherfiARM, etherFiARMAbi, signer);

    log.info("Collecting fees from EtherFi ARM");
    await collectFees({ signer, arm });
  },
});
