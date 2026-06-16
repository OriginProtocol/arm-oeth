import { ethers } from "ethers";

import { action } from "../lib/action";
import { pauseARM } from "../admin";
import { mainnet } from "../../utils/addresses";
const armAbi = require("../../../abis/LidoARM.json");

action({
  name: "pauseLido",
  description: "Pause the Lido ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.lidoARM, armAbi, signer);

    log.info("Pausing the Lido ARM");
    await pauseARM({ signer, arm });
  },
});
