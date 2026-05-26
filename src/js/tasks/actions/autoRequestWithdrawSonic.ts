import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { autoRequestWithdraw } from "../liquidityAutomation";
import { sonic } from "../../utils/addresses";
const armAbi = require("../../../abis/OriginARM.json");

action({
  name: "autoRequestWithdrawSonic",
  description: "Request withdrawals from Origin ARM on Sonic",
  chains: [146],
  params: (t) =>
    t
      .addOptionalParam(
        "minAmount",
        "Minimum balance required before a withdrawal request is made (token units).",
        "300",
        types.string,
      )
      .addOptionalParam(
        "thresholdAmount",
        "Threshold above which a withdrawal request is triggered (token units).",
        10000,
        types.float,
      ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(sonic.OriginARM, armAbi, signer);

    log.info("Requesting withdrawals from Origin ARM on Sonic");
    await autoRequestWithdraw({
      signer,
      arm,
      minAmount: args.minAmount,
      thresholdAmount: args.thresholdAmount,
    });
  },
});
