import { ethers } from "ethers";

import { action } from "../lib/action";
import { pauseARM } from "../admin";
import { mainnet } from "../../utils/addresses";
const armAbi = require("../../../abis/EtherFiARM.json");

action({
  name: "pauseEtherFi",
  description: "Pause the EtherFi ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.etherfiARM, armAbi, signer);

    log.info("Pausing the EtherFi ARM");
    await pauseARM({ signer, arm });
  },
});
