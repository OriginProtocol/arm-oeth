import { ethers } from "ethers";

import { action } from "../lib/action";
import { autoRequestWithdraw } from "../liquidityAutomation";
import { sonic } from "../../utils/addresses";
const armAbi = require("../../../abis/OriginARM.json");

action({
  name: "autoRequestWithdrawSonic",
  description: "Request withdrawals from Origin ARM on Sonic",
  chains: [146],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(sonic.OriginARM, armAbi, signer);

    log.info("Requesting withdrawals from Origin ARM on Sonic");
    await autoRequestWithdraw({
      signer,
      arm,
      minAmount: "300",
      thresholdAmount: 10000,
    });
  },
});
