import { types } from "hardhat/config";

import { action } from "../lib/action";
import { resolveMainnetARM } from "../lib/arm";
import { setARMBuffer } from "../admin";

action({
  name: "setARMBufferAction",
  description: "Set ARM Buffer - Mainnet",
  chains: [1],
  params: (t) =>
    t
      .addParam(
        "arm",
        "ARM to set buffer for: lido, etherfi, ethena, or oeth",
        undefined,
        types.string,
      )
      .addParam(
        "buffer",
        "The new buffer value, where 0.1 = 10% and 1 = 100%",
        undefined,
        types.float,
      ),
  run: async ({ signer, log, args }) => {
    const arm = resolveMainnetARM({
      arm: String(args.arm),
      signer,
    });
    log.info(`Setting ${arm.name} ARM buffer to ${args.buffer}`);
    await setARMBuffer({ signer, arm: arm.contract, buffer: args.buffer });
  },
});
