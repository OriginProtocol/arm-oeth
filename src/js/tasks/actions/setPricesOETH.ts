import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { setPrices } from "../armPrices";
import { setPricesForBases } from "../../utils/priceActionUtils";
import { mainnet } from "../../utils/addresses";
const armAbi = require("../../../abis/OriginARM.json");

action({
  name: "setPricesOETH",
  description: "Set prices for OETH ARM",
  chains: [1],
  // Price points are operator-overridable from the scheduled command in
  // talos (talos UI → schedules → command field). Defaults match what
  // was hardcoded previously so existing seed commands without overrides
  // keep their old behavior.
  params: (t) =>
    t
      .addOptionalParam(
        "buyPrice",
        "Exact buy price; when set, sellPrice must also be set (WETH per base asset).",
        undefined,
        types.float,
      )
      .addOptionalParam(
        "sellPrice",
        "Exact sell price; when set, buyPrice must also be set (base asset per WETH).",
        undefined,
        types.float,
      )
      .addOptionalParam(
        "maxBuyPrice",
        "Upper bound for buy-side price (WETH per OETH).",
        0.9995,
        types.float,
      )
      .addOptionalParam(
        "minBuyPrice",
        "Lower bound for buy-side price (WETH per OETH).",
        0.996,
        types.float,
      )
      .addOptionalParam(
        "maxSellPrice",
        "Upper bound for sell-side price (OETH per WETH).",
        0.9999,
        types.float,
      )
      .addOptionalParam(
        "minSellPrice",
        "Lower bound for sell-side price (OETH per WETH).",
        0.9995,
        types.float,
      )
      .addOptionalParam(
        "amount",
        "DEX swap amount used to fetch the reference price quote.",
        10,
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
        1.0,
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
        0.3,
        types.float,
      )
      .addOptionalParam(
        "fee",
        "Swap fee in basis points used by setPrices when computing target prices.",
        5,
        types.float,
      ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.OethARM, armAbi, signer);

    log.info("Setting prices for OETH ARM");
    await setPricesForBases({
      setPrices,
      bases: ["OETH", "WOETH"],
      options: {
        signer,
        arm,
        armName: "Oeth",
        buyPrice: args.buyPrice,
        sellPrice: args.sellPrice,
        maxSellPrice: args.maxSellPrice,
        minSellPrice: args.minSellPrice,
        maxBuyPrice: args.maxBuyPrice,
        minBuyPrice: args.minBuyPrice,
        kyber: args.kyber,
        inch: args.inch,
        amount: args.amount,
        tolerance: args.tolerance,
        fee: args.fee,
        offset: args.offset,
        dynamicOffset: args.dynamicOffset,
        dynamicOffsetFullSpreadPrice: args.dynamicOffsetFullSpreadPrice,
        priceOffset: true,
        blockTag: "latest",
      },
    });
  },
});
