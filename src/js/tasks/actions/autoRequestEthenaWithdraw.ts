import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { requestEthenaWithdrawals } from "../ethenaQueue";
import { runForBases } from "../../utils/priceActionUtils";
import { mainnet } from "../../utils/addresses";
const erc20Abi = require("../../../abis/ERC20.json");
const ethenaARMAbi = require("../../../abis/EthenaARM.json");

action({
  name: "autoRequestEthenaWithdraw",
  description: "Request Ethena withdrawals from Ethena ARM",
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
    const susde = new ethers.Contract(mainnet.sUSDe, erc20Abi, signer);
    const arm = new ethers.Contract(mainnet.ethenaARM, ethenaARMAbi, signer);

    log.info("Requesting Ethena withdrawals");
    await runForBases({
      bases: ["SUSDE"],
      actionName: "Requesting withdrawals",
      fn: requestEthenaWithdrawals,
      options: {
        signer,
        susde,
        arm,
        armName: "Ethena",
        minAmount: args.minAmount,
        thresholdAmount: args.thresholdAmount,
      },
    });
  },
});
