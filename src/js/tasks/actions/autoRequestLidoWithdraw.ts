import { ethers } from "ethers";

import { action } from "../lib/action";
import { requestLidoWithdrawals } from "../lidoQueue";
import { mainnet } from "../../utils/addresses";
const erc20Abi = require("../../../abis/ERC20.json");
const lidoARMAbi = require("../../../abis/LidoARM.json");

action({
  name: "autoRequestLidoWithdraw",
  description: "Request Lido withdrawals from Lido ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const steth = new ethers.Contract(mainnet.stETH, erc20Abi, signer);
    const arm = new ethers.Contract(mainnet.lidoARM, lidoARMAbi, signer);

    log.info("Requesting Lido withdrawals");
    await requestLidoWithdrawals({
      signer,
      steth,
      arm,
      minAmount: "0.1",
      thresholdAmount: 120,
      maxAmount: 300,
    });
  },
});
