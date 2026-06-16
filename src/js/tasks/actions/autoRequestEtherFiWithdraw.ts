import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { requestEtherFiWithdrawals } from "../etherfiQueue";
import { runForBases } from "../../utils/priceActionUtils";
import { mainnet } from "../../utils/addresses";
const erc20Abi = require("../../../abis/ERC20.json");
const etherFiARMAbi = require("../../../abis/EtherFiARM.json");

action({
  name: "autoRequestEtherFiWithdraw",
  description: "Request EtherFi withdrawals from EtherFi ARM",
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
    const eeth = new ethers.Contract(mainnet.eETH, erc20Abi, signer);
    const arm = new ethers.Contract(mainnet.etherfiARM, etherFiARMAbi, signer);

    log.info("Requesting EtherFi withdrawals");
    await runForBases({
      bases: ["EETH", "WEETH"],
      actionName: "Requesting withdrawals",
      fn: requestEtherFiWithdrawals,
      options: {
        signer,
        eeth,
        arm,
        armName: "EtherFi",
        minAmount: args.minAmount,
        thresholdAmount: args.thresholdAmount,
      },
    });
  },
});
