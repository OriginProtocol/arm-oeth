import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { claimPaxosWithdrawals } from "../paxosQueue";
import { runForBases } from "../../utils/priceActionUtils";
import { mainnet } from "../../utils/addresses";
const multiAssetARMAbi = require("../../../abis/MultiAssetARM.json");

action({
  name: "autoClaimUSDWithdraw",
  description: "Claim USDC settled by Paxos redemptions for the USD ARM",
  chains: [1],
  params: (t) =>
    t.addOptionalParam(
      "minAmount",
      "Minimum settled amount required before a claim is made (token units).",
      100,
      types.float,
    ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.usdARM, multiAssetARMAbi, signer);

    log.info("Claiming USD ARM withdrawals settled by Paxos");
    await runForBases({
      bases: ["PYUSD", "USDG"],
      actionName: "Claiming withdrawals",
      fn: claimPaxosWithdrawals,
      options: {
        signer,
        arm,
        armName: "USD",
        minAmount: args.minAmount,
      },
    });
  },
});
