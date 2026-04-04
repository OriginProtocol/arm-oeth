import { ethers } from "ethers";

import { action } from "../lib/action";
import { collectFees } from "../admin";
import { mainnet } from "../../utils/addresses";
const armAbi = require("../../../abis/OriginARM.json");

action({
  name: "collectOETHFees",
  description: "Collect fees from OETH ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.OethARM, armAbi, signer);

    log.info("Collecting fees from OETH ARM");
    await collectFees({ signer, arm });
  },
});
