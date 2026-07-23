import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { setPrices } from "../armPrices";
import { setPricesForBases } from "../../utils/priceActionUtils";
import { mainnet } from "../../utils/addresses";
const multiAssetARMAbi = require("../../../abis/MultiAssetARM.json");

const LIDO_BASES = new Set(["STETH", "WSTETH"]);
const SUPPORTED_BASES = new Set(["STETH", "WSTETH", "EETH", "WEETH"]);

const lidoDefaults = {
  maxBuyPrice: 0.9999,
  minBuyPrice: 0.998,
  maxSellPrice: 1,
  minSellPrice: 0.9999,
  tolerance: 0.1,
  inch: true,
  kyber: false,
};

const etherFiDefaults = {
  maxBuyPrice: 0.9998,
  minBuyPrice: 0.99,
  maxSellPrice: 1,
  minSellPrice: 0.99996,
  tolerance: 0.09,
  inch: false,
  kyber: true,
};

action({
  name: "setPricesWETH",
  description: "Set prices for WETH ARM",
  chains: [1],
  params: (t) =>
    t
      .addOptionalParam(
        "bases",
        "Comma-separated list of base assets to set prices for.",
        "STETH,WSTETH,EETH,WEETH",
        types.string,
      )
      .addOptionalParam(
        "buyPrice",
        "Exact buy price; when set, sellPrice must also be set (WETH per base asset).",
        undefined,
        types.float,
      )
      .addOptionalParam(
        "sellPrice",
        "Exact sell price; when set, buyPrice must also be set (WETH per base asset).",
        undefined,
        types.float,
      )
      .addOptionalParam(
        "buyAmount",
        "WETH remaining at the buy price, as an integer in native token units.",
        undefined,
        types.string,
      )
      .addOptionalParam(
        "sellAmount",
        "Base asset remaining at the sell price, as an integer in native token units.",
        undefined,
        types.string,
      )
      .addOptionalParam(
        "maxBuyPrice",
        "Override the profile upper bound for the buy-side price.",
        undefined,
        types.float,
      )
      .addOptionalParam(
        "minBuyPrice",
        "Override the profile lower bound for the buy-side price.",
        undefined,
        types.float,
      )
      .addOptionalParam(
        "maxSellPrice",
        "Override the profile upper bound for the sell-side price.",
        undefined,
        types.float,
      )
      .addOptionalParam(
        "minSellPrice",
        "Override the profile lower bound for the sell-side price.",
        undefined,
        types.float,
      )
      .addOptionalParam(
        "amount",
        "Override the DEX swap amount used to fetch reference price quotes.",
        undefined,
        types.float,
      )
      .addOptionalParam(
        "inch",
        "Override whether 1Inch is the aggregator price source.",
        undefined,
        types.boolean,
      )
      .addOptionalParam(
        "kyber",
        "Override whether Kyber is the aggregator price source.",
        undefined,
        types.boolean,
      )
      .addOptionalParam(
        "offset",
        "Price offset applied to aggregator quotes.",
        0.2,
        types.float,
      )
      .addOptionalParam(
        "dynamicOffset",
        "Use a dynamic offset that scales from zero at cross price to the DEX spread at the full-spread price.",
        false,
        types.boolean,
      )
      .addOptionalParam(
        "dynamicOffsetFullSpreadPrice",
        "DEX sell price where dynamic offset reaches 100% of the DEX spread.",
        0.999,
        types.float,
      )
      .addOptionalParam(
        "tolerance",
        "Override the profile tolerance used when comparing target and current prices.",
        undefined,
        types.float,
      )
      .addOptionalParam(
        "fee",
        "Swap fee in basis points used when computing target prices.",
        2,
        types.float,
      ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.wethARM, multiAssetARMAbi, signer);
    const bases = String(args.bases)
      .split(",")
      .map((base) => base.trim().toUpperCase())
      .filter(Boolean);

    const unsupported = bases.filter((base) => !SUPPORTED_BASES.has(base));
    if (unsupported.length > 0) {
      throw new Error(
        `Unsupported WETH ARM base asset${unsupported.length === 1 ? "" : "s"}: ${unsupported.join(", ")}`,
      );
    }
    if (bases.length === 0) {
      throw new Error("At least one WETH ARM base asset is required");
    }

    const aggregatorOverridden =
      args.inch !== undefined || args.kyber !== undefined;

    log.info("Setting prices for WETH ARM");
    for (const base of bases) {
      const defaults = LIDO_BASES.has(base) ? lidoDefaults : etherFiDefaults;
      await setPricesForBases({
        setPrices,
        bases: [base],
        options: {
          signer,
          arm,
          armName: "WETH",
          buyPrice: args.buyPrice,
          sellPrice: args.sellPrice,
          buyAmount: args.buyAmount,
          sellAmount: args.sellAmount,
          maxSellPrice: args.maxSellPrice ?? defaults.maxSellPrice,
          minSellPrice: args.minSellPrice ?? defaults.minSellPrice,
          maxBuyPrice: args.maxBuyPrice ?? defaults.maxBuyPrice,
          minBuyPrice: args.minBuyPrice ?? defaults.minBuyPrice,
          kyber: aggregatorOverridden ? Boolean(args.kyber) : defaults.kyber,
          inch: aggregatorOverridden ? Boolean(args.inch) : defaults.inch,
          amount: args.amount ?? 20,
          tolerance: args.tolerance ?? defaults.tolerance,
          fee: args.fee,
          offset: args.offset,
          dynamicOffset: args.dynamicOffset,
          dynamicOffsetFullSpreadPrice: args.dynamicOffsetFullSpreadPrice,
          priceOffset: true,
          blockTag: "latest",
        },
      });
    }
  },
});
