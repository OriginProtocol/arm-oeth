import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { setPrices } from "../armPrices";
import { setPricesForBases } from "../../utils/priceActionUtils";
import { resolveEthenaAggregatorAmount } from "../../utils/ethenaPricing";
import { mainnet } from "../../utils/addresses";
const ethenaARMAbi = require("../../../abis/EthenaARM.json");

action({
  name: "setPricesEthena",
  description: "Set prices for Ethena ARM",
  chains: [1],
  // Price points are operator-overridable from the scheduled command in
  // talos (talos UI → schedules → command field). Defaults match what
  // was hardcoded previously so existing seed commands without overrides
  // keep their old behavior.
  params: (t) =>
    t
      .addOptionalParam(
        "maxBuyPrice",
        "Upper bound for buy-side price (USDe per sUSDe).",
        0.99985,
        types.float,
      )
      .addOptionalParam(
        "minBuyPrice",
        "Lower bound for buy-side price (USDe per sUSDe).",
        0.998,
        types.float,
      )
      .addOptionalParam(
        "maxSellPrice",
        "Upper bound for sell-side price (sUSDe per USDe).",
        0.99999,
        types.float,
      )
      .addOptionalParam(
        "minSellPrice",
        "Lower bound for sell-side price (sUSDe per USDe).",
        0.99996,
        types.float,
      )
      .addOptionalParam(
        "amount",
        "Override for the reference swap amount used when fetching aggregator quotes.",
        undefined,
        types.float,
      )
      .addOptionalParam(
        "inch",
        "Use 1Inch as the aggregator price source.",
        false,
        types.boolean,
      )
      .addOptionalParam(
        "kyber",
        "Use Kyber as the aggregator price source.",
        true,
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
        "Tolerance used when comparing target and current prices.",
        0.09,
        types.float,
      )
      .addOptionalParam(
        "fee",
        "Swap fee in basis points used by setPrices when computing target prices.",
        2,
        types.float,
      ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.ethenaARM, ethenaARMAbi, signer);

    log.info("Setting prices for Ethena ARM");
    const amount = await resolveEthenaAggregatorAmount({
      arm,
      amount: args.amount,
      log,
      blockTag: "latest",
    });
    if (amount === undefined) return;

    await setPricesForBases({
      setPrices,
      bases: ["SUSDE"],
      options: {
        signer,
        arm,
        armName: "Ethena",
        maxSellPrice: args.maxSellPrice,
        minSellPrice: args.minSellPrice,
        maxBuyPrice: args.maxBuyPrice,
        minBuyPrice: args.minBuyPrice,
        kyber: args.kyber,
        inch: args.inch,
        amount,
        tolerance: args.tolerance,
        fee: args.fee,
        offset: args.offset,
        dynamicOffset: args.dynamicOffset,
        dynamicOffsetFullSpreadPrice: args.dynamicOffsetFullSpreadPrice,
        priceOffset: true,
        blockTag: "latest",
        wrapped: true,
      },
    });
  },
});
