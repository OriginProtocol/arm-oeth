import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { requestPaxosWithdrawals } from "../paxosQueue";
import { runForBases } from "../../utils/priceActionUtils";
import { mainnet } from "../../utils/addresses";
const multiAssetARMAbi = require("../../../abis/MultiAssetARM.json");

action({
  name: "autoRequestUSDWithdraw",
  description:
    "Request and submit Paxos redemptions of PYUSD/USDG from the USD ARM",
  chains: [1],
  params: (t) =>
    t
      .addOptionalParam(
        "minAmount",
        "Minimum balance required before a withdrawal request is made (token units).",
        "100",
        types.string,
      )
      .addOptionalParam(
        "thresholdAmount",
        "Threshold above which a withdrawal request is triggered (token units).",
        1000,
        types.float,
      ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.usdARM, multiAssetARMAbi, signer);

    log.info("Requesting USD ARM withdrawals via Paxos");
    await runForBases({
      bases: ["PYUSD", "USDG"],
      actionName: "Requesting withdrawals",
      fn: requestPaxosWithdrawals,
      options: {
        signer,
        arm,
        armName: "USD",
        minAmount: args.minAmount,
        thresholdAmount: args.thresholdAmount,
      },
    });
  },
});
