import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { claimArmRedeems } from "../armRedeemQueue";
import { mainnet } from "../../utils/addresses";
const ethenaARMAbi = require("../../../abis/EthenaARM.json");
const etherFiARMAbi = require("../../../abis/EtherFiARM.json");
const lidoARMAbi = require("../../../abis/LidoARM.json");

const ARMS = {
  ethena: {
    abi: ethenaARMAbi,
    address: mainnet.ethenaARM,
    name: "Ethena",
  },
  etherfi: {
    abi: etherFiARMAbi,
    address: mainnet.etherfiARM,
    name: "EtherFi",
  },
  lido: {
    abi: lidoARMAbi,
    address: mainnet.lidoARM,
    name: "Lido",
  },
};

action({
  name: "claimRedeem",
  description:
    "Claim one or more matured LP redeem requests on behalf of users",
  chains: [1],
  params: (t) =>
    t
      .addParam(
        "arm",
        "ARM to claim from: lido, etherfi, or ethena",
        undefined,
        types.string,
      )
      .addParam(
        "ids",
        "Comma-separated LP withdrawal request ids to claim, eg 12,13,14",
        undefined,
        types.string,
      ),
  run: async ({ signer, log, args }) => {
    const armKey = String(args.arm).toLowerCase();
    const armConfig = ARMS[armKey as keyof typeof ARMS];

    if (!armConfig) {
      throw new Error(
        `Unsupported ARM "${args.arm}" (use lido, etherfi, or ethena)`,
      );
    }

    const arm = new ethers.Contract(armConfig.address, armConfig.abi, signer);
    await claimArmRedeems({
      arm,
      armName: armConfig.name,
      ids: args.ids,
      log,
    });
  },
});
