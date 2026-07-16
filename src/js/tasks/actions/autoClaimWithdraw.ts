import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { autoClaimWithdraw } from "../liquidityAutomation";
import { runForBases } from "../../utils/priceActionUtils";
import { mainnet } from "../../utils/addresses";
const erc20Abi = require("../../../abis/ERC20.json");
const oethARMAbi = require("../../../abis/OethARM.json");
const vaultAbi = require("../../../abis/vault.json");

action({
  name: "autoClaimWithdraw",
  description: "Claim withdrawals from OETH ARM",
  chains: [1],
  params: (t) =>
    t.addOptionalParam(
      "id",
      "Specific OETH withdrawal request identifier to claim. (default: all)",
      undefined,
      types.string,
    ),
  run: async ({ signer, log, args }) => {
    const liquidityAsset = new ethers.Contract(mainnet.WETH, erc20Abi, signer);
    const vault = new ethers.Contract(mainnet.OETHVaultProxy, vaultAbi, signer);
    const arm = new ethers.Contract(mainnet.OethARM, oethARMAbi, signer);

    log.info("Claiming withdrawals from OETH ARM");
    await runForBases({
      bases: ["OETH", "WOETH"],
      actionName: "Claiming withdrawals",
      fn: autoClaimWithdraw,
      options: {
        signer,
        liquidityAsset,
        arm,
        armName: "Oeth",
        vault,
        confirm: true,
        id: args.id,
      },
    });
  },
});
