import { ethers } from "ethers";

import { action } from "../lib/action";
import { autoRequestWithdraw } from "../liquidityAutomation";
import { mainnet } from "../../utils/addresses";
const oethARMAbi = require("../../../abis/OethARM.json");

action({
  name: "autoRequestWithdraw",
  description: "Request withdrawals from OETH ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.OethARM, oethARMAbi, signer);

    log.info("Requesting withdrawals from OETH ARM");
    await autoRequestWithdraw({
      signer,
      arm,
      minAmount: "0.1",
      thresholdAmount: 10,
    });
  },
});
