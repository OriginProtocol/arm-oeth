import { ethers } from "ethers";

import { action } from "../lib/action";
import { claimLidoWithdrawals } from "../lidoQueue";
import { mainnet } from "../../utils/addresses";
const lidoARMAbi = require("../../../abis/LidoARM.json");
const lidoWithdrawQueueAbi = require("../../../abis/LidoWithdrawQueue.json");

action({
  name: "autoClaimLidoWithdraw",
  description: "Claim Lido withdrawals from Lido ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.lidoARM, lidoARMAbi, signer);
    const withdrawalQueue = new ethers.Contract(
      mainnet.lidoWithdrawalQueue,
      lidoWithdrawQueueAbi,
      signer
    );

    log.info("Claiming Lido withdrawals");
    await claimLidoWithdrawals({ signer, arm, withdrawalQueue });
  },
});
