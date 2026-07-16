import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { claimLidoWithdrawals } from "../lidoQueue";
import { runForBases } from "../../utils/priceActionUtils";
import { mainnet } from "../../utils/addresses";
const lidoARMAbi = require("../../../abis/LidoARM.json");
const lidoWithdrawQueueAbi = require("../../../abis/LidoWithdrawQueue.json");

action({
  name: "autoClaimLidoWithdraw",
  description: "Claim Lido withdrawals from Lido ARM",
  chains: [1],
  params: (t) =>
    t.addOptionalParam(
      "id",
      "Specific Lido withdrawal request identifier to claim. (default: all)",
      undefined,
      types.string,
    ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.lidoARM, lidoARMAbi, signer);
    const withdrawalQueue = new ethers.Contract(
      mainnet.lidoWithdrawalQueue,
      lidoWithdrawQueueAbi,
      signer,
    );

    log.info("Claiming Lido withdrawals");
    await runForBases({
      bases: ["STETH", "WSTETH"],
      actionName: "Claiming withdrawals",
      fn: claimLidoWithdrawals,
      options: {
        signer,
        arm,
        armName: "Lido",
        withdrawalQueue,
        id: args.id,
      },
    });
  },
});
