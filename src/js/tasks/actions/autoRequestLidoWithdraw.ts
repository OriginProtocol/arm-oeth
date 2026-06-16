import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { requestLidoWithdrawals } from "../lidoQueue";
import { runForBases } from "../../utils/priceActionUtils";
import { mainnet } from "../../utils/addresses";
const erc20Abi = require("../../../abis/ERC20.json");
const lidoARMAbi = require("../../../abis/LidoARM.json");

action({
  name: "autoRequestLidoWithdraw",
  description: "Request Lido withdrawals from Lido ARM",
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
        "Maximum amount per withdrawal request (token units).",
        300,
        types.float,
      ),
  run: async ({ signer, log, args }) => {
    const steth = new ethers.Contract(mainnet.stETH, erc20Abi, signer);
    const arm = new ethers.Contract(mainnet.lidoARM, lidoARMAbi, signer);

    log.info("Requesting Lido withdrawals");
    await runForBases({
      bases: ["STETH", "WSTETH"],
      actionName: "Requesting withdrawals",
      fn: requestLidoWithdrawals,
      options: {
        signer,
        steth,
        arm,
        armName: "Lido",
        minAmount: args.minAmount,
        thresholdAmount: args.thresholdAmount,
        maxAmount: args.maxAmount,
      },
    });
  },
});
