import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { requestEtherFiWithdrawals } from "../etherfiQueue";
import { runForBases } from "../../utils/priceActionUtils";
import { mainnet } from "../../utils/addresses";
const multiAssetARMAbi = require("../../../abis/MultiAssetARM.json");

action({
  name: "autoRequestWETHEtherFiWithdraw",
  description: "Request EtherFi withdrawals from WETH ARM",
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
    const arm = new ethers.Contract(mainnet.wethARM, multiAssetARMAbi, signer);

    log.info("Requesting EtherFi withdrawals from WETH ARM");
    await runForBases({
      bases: ["EETH", "WEETH"],
      actionName: "Requesting withdrawals",
      fn: requestEtherFiWithdrawals,
      options: {
        signer,
        arm,
        armName: "WETH",
        minAmount: args.minAmount,
        thresholdAmount: args.thresholdAmount,
      },
    });
  },
});
