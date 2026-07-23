import { types } from "hardhat/config";

import { action } from "../lib/action";
import { resolveMainnetARM } from "../lib/arm";
import { setTotalAssetsCap } from "../admin";

action({
  name: "setTotalAssetsCapAction",
  description: "Set Total Assets Cap - Mainnet",
  chains: [1],
  params: (t) =>
    t
      .addParam(
        "arm",
        "ARM to set total assets cap for: lido, etherfi, ethena, oeth, or usdc",
        undefined,
        types.string,
      )
      .addParam(
        "cap",
        "Total assets cap in liquidity asset units, where 100000 = 100,000 USDe/USDC",
        undefined,
        types.float,
      ),
  run: async ({ signer, log, args }) => {
    const arm = resolveMainnetARM({
      arm: String(args.arm),
      signer,
    });
    log.info(`Setting ${arm.name} ARM total assets cap to ${args.cap}`);
    await setTotalAssetsCap({
      signer,
      arm: arm.contract,
      armName: arm.name,
      cap: args.cap,
      decimals: arm.decimals,
    });
  },
});
