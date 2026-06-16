import { ethers } from "ethers";

import { action } from "../lib/action";
import { pauseARM } from "../admin";
import { mainnet } from "../../utils/addresses";
const armAbi = require("../../../abis/EthenaARM.json");

action({
  name: "pauseEthena",
  description: "Pause the Ethena ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.ethenaARM, armAbi, signer);

    log.info("Pausing the Ethena ARM");
    await pauseARM({ signer, arm });
  },
});
