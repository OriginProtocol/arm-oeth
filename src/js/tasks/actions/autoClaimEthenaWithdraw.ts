import { ethers } from "ethers";

import { action } from "../lib/action";
import { claimEthenaWithdrawals } from "../ethenaQueue";
import { mainnet } from "../../utils/addresses";
const ethenaARMAbi = require("../../../abis/EthenaARM.json");

action({
  name: "autoClaimEthenaWithdraw",
  description: "Claim Ethena withdrawals from Ethena ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.ethenaARM, ethenaARMAbi, signer);

    log.info("Claiming Ethena withdrawals");
    await claimEthenaWithdrawals({ signer, arm });
  },
});
