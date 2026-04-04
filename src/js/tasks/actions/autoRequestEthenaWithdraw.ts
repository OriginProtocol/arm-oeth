import { ethers } from "ethers";

import { action } from "../lib/action";
import { requestEthenaWithdrawals } from "../ethenaQueue";
import { mainnet } from "../../utils/addresses";
const erc20Abi = require("../../../abis/ERC20.json");
const ethenaARMAbi = require("../../../abis/EthenaARM.json");

action({
  name: "autoRequestEthenaWithdraw",
  description: "Request Ethena withdrawals from Ethena ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const susde = new ethers.Contract(mainnet.sUSDe, erc20Abi, signer);
    const arm = new ethers.Contract(mainnet.ethenaARM, ethenaARMAbi, signer);

    log.info("Requesting Ethena withdrawals");
    await requestEthenaWithdrawals({
      signer,
      susde,
      arm,
      minAmount: "100",
      thresholdAmount: 1000,
    });
  },
});
