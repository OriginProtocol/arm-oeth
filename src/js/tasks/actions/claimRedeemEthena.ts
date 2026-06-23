import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { claimArmRedeems } from "../armRedeemQueue";
import { mainnet } from "../../utils/addresses";
const ethenaARMAbi = require("../../../abis/EthenaARM.json");

action({
  name: "claimRedeemEthena",
  description:
    "Claim one or more matured LP redeem requests on behalf of users from the Ethena ARM",
  chains: [1],
  params: (t) =>
    t.addParam(
      "ids",
      "Comma-separated LP withdrawal request ids to claim, eg 12,13,14",
      undefined,
      types.string,
    ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.ethenaARM, ethenaARMAbi, signer);
    await claimArmRedeems({ arm, armName: "Ethena", ids: args.ids, log });
  },
});
