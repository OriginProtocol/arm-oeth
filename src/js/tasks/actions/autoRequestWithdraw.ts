import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { autoRequestWithdraw } from "../liquidityAutomation";
import { mainnet } from "../../utils/addresses";
const oethARMAbi = require("../../../abis/OethARM.json");

action({
  name: "autoRequestWithdraw",
  description: "Request withdrawals from OETH ARM",
  chains: [1],
  params: (t) =>
    t
      .addOptionalParam(
        "minAmount",
        "Minimum balance required before a withdrawal request is made (token units).",
        "0.1",
        types.string,
      )
      .addOptionalParam(
        "thresholdAmount",
        "Threshold above which a withdrawal request is triggered (token units).",
        10,
        types.float,
      ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.OethARM, oethARMAbi, signer);

    log.info("Requesting withdrawals from OETH ARM");
    await autoRequestWithdraw({
      signer,
      arm,
      minAmount: args.minAmount,
      thresholdAmount: args.thresholdAmount,
    });
  },
});
