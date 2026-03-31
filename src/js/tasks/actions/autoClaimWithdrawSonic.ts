import { ethers } from "ethers";

import { action } from "../lib/action";
import { autoClaimWithdraw } from "../liquidityAutomation";
import { logTxDetails } from "../../utils/txLogger";
import { sonic } from "../../utils/addresses";
const erc20Abi = require("../../../abis/ERC20.json");
const armAbi = require("../../../abis/OriginARM.json");
const vaultAbi = require("../../../abis/vault.json");

action({
  name: "autoClaimWithdrawSonic",
  description: "Claim withdrawals from Origin ARM on Sonic and allocate",
  chains: [146],
  run: async ({ signer, log }) => {
    const liquidityAsset = new ethers.Contract(sonic.WS, erc20Abi, signer);
    const vault = new ethers.Contract(
      sonic.OSonicVaultProxy,
      vaultAbi,
      signer
    );
    const arm = new ethers.Contract(sonic.OriginARM, armAbi, signer);

    log.info("Claiming withdrawals from Origin ARM on Sonic");
    const requestIds = await autoClaimWithdraw({
      signer,
      liquidityAsset,
      arm,
      vault,
      confirm: true,
    });

    log.info(`Claimed requests "${requestIds}"`);

    // If any requests were claimed, allocate excess liquidity to the lending market
    if (requestIds?.length > 0) {
      let gasLimit = await (arm as any).connect(signer).allocate.estimateGas();
      gasLimit = (gasLimit * 12n) / 10n;

      const tx = await (arm as any).allocate({ gasLimit });
      await logTxDetails(tx, "allocate");
    }
  },
});
