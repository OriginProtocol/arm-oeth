import { ethers } from "ethers";

import { action } from "../lib/action";
import { requestEtherFiWithdrawals } from "../etherfiQueue";
import { mainnet } from "../../utils/addresses";
const erc20Abi = require("../../../abis/ERC20.json");
const etherFiARMAbi = require("../../../abis/EtherFiARM.json");

action({
  name: "autoRequestEtherFiWithdraw",
  description: "Request EtherFi withdrawals from EtherFi ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const eeth = new ethers.Contract(mainnet.eETH, erc20Abi, signer);
    const arm = new ethers.Contract(mainnet.etherfiARM, etherFiARMAbi, signer);

    log.info("Requesting EtherFi withdrawals");
    await requestEtherFiWithdrawals({
      signer,
      eeth,
      arm,
      minAmount: "0.1",
      thresholdAmount: 10,
    });
  },
});
