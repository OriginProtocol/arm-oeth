import { ethers } from "ethers";

import { action } from "../lib/action";
import { collectFees } from "../admin";
import { mainnet } from "../../utils/addresses";
const lidoARMAbi = require("../../../abis/LidoARM.json");

action({
  name: "collectLidoFees",
  description: "Collect fees from Lido ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.lidoARM, lidoARMAbi, signer);

    log.info("Collecting fees from Lido ARM");
    await collectFees({ signer, arm });
  },
});
