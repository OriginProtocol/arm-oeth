import { types } from "hardhat/config";

import { action } from "../lib/action";
import { resolveMainnetARM } from "../lib/arm";
import { setLiquidityProviderCaps } from "../admin";

action({
  name: "setLiquidityProviderCapsAction",
  description: "Set Liquidity Provider Caps - Mainnet",
  chains: [1],
  params: (t) =>
    t
      .addParam(
        "arm",
        "ARM to set liquidity provider caps for: lido, etherfi, ethena, oeth, or usdc",
        undefined,
        types.string,
      )
      .addParam(
        "accounts",
        "Comma-separated list of liquidity provider addresses",
        undefined,
        types.string,
      )
      .addParam(
        "cap",
        "Deposit cap per account in liquidity asset units, where 20000 = 20,000 USDe/USDC",
        undefined,
        types.float,
      ),
  run: async ({ signer, log, args }) => {
    const arm = resolveMainnetARM({
      arm: String(args.arm),
      signer,
    });
    log.info(`Setting ${arm.name} ARM liquidity provider caps to ${args.cap}`);
    await setLiquidityProviderCaps({
      signer,
      arm: arm.contract,
      armName: arm.name,
      accounts: args.accounts,
      cap: args.cap,
      decimals: arm.decimals,
    });
  },
});
