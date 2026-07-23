import { types } from "hardhat/config";

import { action } from "../lib/action";
import { resolveMainnetARM } from "../lib/arm";
import { claimArmRedeems } from "../armRedeemQueue";

action({
  name: "claimRedeem",
  description:
    "Claim one or more matured LP redeem requests on behalf of users",
  chains: [1],
  params: (t) =>
    t
      .addParam(
        "arm",
        "ARM to claim from: lido, etherfi, ethena, or usdc",
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
    const arm = resolveMainnetARM({
      arm: String(args.arm),
      signer,
      supportedArms: ["lido", "etherfi", "ethena", "usdc"],
    });
    await claimArmRedeems({
      arm: arm.contract,
      armName: arm.name,
      ids: args.ids,
      log,
    });
  },
});
