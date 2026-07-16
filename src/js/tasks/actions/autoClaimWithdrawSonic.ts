import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { autoClaimWithdraw } from "../liquidityAutomation";
import { callAllocate, estimateAllocateGas } from "../../utils/arm";
import { runForBases } from "../../utils/priceActionUtils";
import { logTxDetails } from "../../utils/txLogger";
import { sonic } from "../../utils/addresses";
const erc20Abi = require("../../../abis/ERC20.json");
const armAbi = require("../../../abis/OriginARM.json");
const vaultAbi = require("../../../abis/vault.json");

action({
  name: "autoClaimWithdrawSonic",
  description: "Claim withdrawals from Origin ARM on Sonic and allocate",
  chains: [146],
  params: (t) =>
    t.addOptionalParam(
      "id",
      "Specific OS withdrawal request identifier to claim. (default: all)",
      undefined,
      types.string,
    ),
  run: async ({ signer, log, args }) => {
    const liquidityAsset = new ethers.Contract(sonic.WS, erc20Abi, signer);
    const vault = new ethers.Contract(sonic.OSonicVaultProxy, vaultAbi, signer);
    const arm = new ethers.Contract(sonic.OriginARM, armAbi, signer);

    log.info("Claiming withdrawals from Origin ARM on Sonic");
    const requestIds = (
      await runForBases({
        bases: ["OS", "WOS"],
        actionName: "Claiming withdrawals",
        fn: autoClaimWithdraw,
        options: {
          signer,
          liquidityAsset,
          arm,
          armName: "Origin",
          vault,
          confirm: true,
          id: args.id,
        },
      })
    )
      .flat()
      .filter((requestId: unknown) => requestId !== undefined);

    log.info(`Claimed requests "${requestIds}"`);

    // If any requests were claimed, allocate excess liquidity to the lending market
    if (requestIds?.length > 0) {
      let gasLimit = await estimateAllocateGas(arm, signer);
      gasLimit = (gasLimit * 12n) / 10n;

      const tx = await callAllocate(arm, signer, { gasLimit });
      await logTxDetails(tx, "allocate");
    }
  },
});
