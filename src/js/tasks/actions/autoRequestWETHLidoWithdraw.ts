import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { requestLidoWithdrawals } from "../lidoQueue";
import { runForBases } from "../../utils/priceActionUtils";
import { mainnet } from "../../utils/addresses";
const multiAssetARMAbi = require("../../../abis/MultiAssetARM.json");

action({
  name: "autoRequestWETHLidoWithdraw",
  description: "Request Lido withdrawals from WETH ARM",
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
        120,
        types.float,
      )
      .addOptionalParam(
        "maxAmount",
        "Maximum amount per Lido withdrawal request (token units).",
        300,
        types.float,
      ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.wethARM, multiAssetARMAbi, signer);

    log.info("Requesting Lido withdrawals from WETH ARM");
    await runForBases({
      bases: ["STETH", "WSTETH"],
      actionName: "Requesting withdrawals",
      fn: requestLidoWithdrawals,
      options: {
        signer,
        arm,
        armName: "WETH",
        minAmount: args.minAmount,
        thresholdAmount: args.thresholdAmount,
        maxAmount: args.maxAmount,
      },
    });
  },
});
