import { types } from "hardhat/config";

import { action } from "../lib/action";
import { resolveMainnetARM } from "../lib/arm";
import { pauseARM } from "../admin";

action({
  name: "pause",
  description: "Pause an ARM - Mainnet",
  chains: [1],
  params: (t) =>
    t.addParam(
      "arm",
      "ARM to pause: lido, etherfi, ethena, oeth, usdc, or weth",
      undefined,
      types.string,
    ),
  run: async ({ signer, log, args }) => {
    const arm = resolveMainnetARM({
      arm: String(args.arm),
      signer,
    });
    log.info(`Pausing the ${arm.name} ARM`);
    await pauseARM({ signer, arm: arm.contract });
  },
});
