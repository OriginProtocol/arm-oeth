import { ethers } from "ethers";

import { action } from "../lib/action";
import { collectFees } from "../admin";
import { sonic } from "../../utils/addresses";
const lidoARMAbi = require("../../../abis/LidoARM.json");

action({
  name: "collectFeesSonic",
  description: "Collect fees from Origin ARM on Sonic",
  chains: [146],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(sonic.OriginARM, lidoARMAbi, signer);

    log.info("Collecting fees from Origin ARM on Sonic");
    await collectFees({ signer, arm });
  },
});
