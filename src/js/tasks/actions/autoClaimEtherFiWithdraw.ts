import { ethers } from "ethers";

import { action } from "../lib/action";
import { claimEtherFiWithdrawals } from "../etherfiQueue";
import { runForBases } from "../../utils/priceActionUtils";
import { mainnet } from "../../utils/addresses";
const etherFiARMAbi = require("../../../abis/EtherFiARM.json");

action({
  name: "autoClaimEtherFiWithdraw",
  description: "Claim EtherFi withdrawals from EtherFi ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.etherfiARM, etherFiARMAbi, signer);

    log.info("Claiming EtherFi withdrawals");
    await runForBases({
      bases: ["EETH", "WEETH"],
      actionName: "Claiming withdrawals",
      fn: claimEtherFiWithdrawals,
      options: {
        signer,
        arm,
        armName: "EtherFi",
      },
    });
  },
});
