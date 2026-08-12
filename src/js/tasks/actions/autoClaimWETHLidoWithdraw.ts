import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { claimLidoWithdrawals } from "../lidoQueue";
import { runForBases } from "../../utils/priceActionUtils";
import { mainnet } from "../../utils/addresses";
const multiAssetARMAbi = require("../../../abis/MultiAssetARM.json");

action({
  name: "autoClaimWETHLidoWithdraw",
  description: "Claim Lido withdrawals from WETH ARM",
  chains: [1],
  params: (t) =>
    t
      .addOptionalParam(
        "id",
        "Specific Lido withdrawal request identifier to claim. (deprecated: use ids)",
        undefined,
        types.string,
      )
      .addOptionalParam(
        "ids",
        "Comma-separated Lido withdrawal request identifiers to claim. (default: all)",
        undefined,
        types.string,
      ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.wethARM, multiAssetARMAbi, signer);

    log.info("Claiming Lido withdrawals from WETH ARM");
    await runForBases({
      bases: ["STETH", "WSTETH"],
      actionName: "Claiming withdrawals",
      fn: claimLidoWithdrawals,
      options: {
        signer,
        arm,
        armName: "WETH",
        id: args.id,
        ids: args.ids,
      },
    });
  },
});
