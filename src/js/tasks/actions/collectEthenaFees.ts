import { ethers } from "ethers";

import { action } from "../lib/action";
import { collectFees } from "../admin";
import { mainnet } from "../../utils/addresses";
const ethenaARMAbi = require("../../../abis/EthenaARM.json");

action({
  name: "collectEthenaFees",
  description: "Collect fees from Ethena ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.ethenaARM, ethenaARMAbi, signer);

    log.info("Collecting fees from Ethena ARM");
    await collectFees({ signer, arm });
  },
});
