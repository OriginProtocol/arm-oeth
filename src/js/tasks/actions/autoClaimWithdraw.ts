import { ethers } from "ethers";

import { action } from "../lib/action";
import { autoClaimWithdraw } from "../liquidityAutomation";
import { mainnet } from "../../utils/addresses";
const erc20Abi = require("../../../abis/ERC20.json");
const oethARMAbi = require("../../../abis/OethARM.json");
const vaultAbi = require("../../../abis/vault.json");

action({
  name: "autoClaimWithdraw",
  description: "Claim withdrawals from OETH ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const liquidityAsset = new ethers.Contract(mainnet.WETH, erc20Abi, signer);
    const vault = new ethers.Contract(
      mainnet.OETHVaultProxy,
      vaultAbi,
      signer
    );
    const arm = new ethers.Contract(mainnet.OethARM, oethARMAbi, signer);

    log.info("Claiming withdrawals from OETH ARM");
    await autoClaimWithdraw({
      signer,
      liquidityAsset,
      arm,
      vault,
      confirm: true,
    });
  },
});
