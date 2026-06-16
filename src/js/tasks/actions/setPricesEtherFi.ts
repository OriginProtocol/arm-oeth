import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { setPrices } from "../armPrices";
import { setPricesForBases } from "../../utils/priceActionUtils";
import { mainnet } from "../../utils/addresses";
const etherFiARMAbi = require("../../../abis/EtherFiARM.json");

action({
  name: "setPricesEtherFi",
  description: "Set prices for EtherFi ARM",
  chains: [1],
  // Price points are operator-overridable from the scheduled command in
  // talos (talos UI → schedules → command field). Defaults match what
  // was hardcoded previously so existing seed commands without overrides
  // keep their old behavior.
  params: (t) =>
    t
      .addOptionalParam(
        "maxBuyPrice",
        "Upper bound for buy-side price (ETH per eETH).",
        0.9998,
        types.float,
      )
      .addOptionalParam(
        "minBuyPrice",
        "Lower bound for buy-side price (ETH per eETH).",
        0.99,
        types.float,
      )
      .addOptionalParam(
        "maxSellPrice",
        "Upper bound for sell-side price (eETH per ETH).",
        1.0,
        types.float,
      )
      .addOptionalParam(
        "minSellPrice",
        "Lower bound for sell-side price (eETH per ETH).",
        0.99996,
        types.float,
      )
      .addOptionalParam(
        "amount",
        "Reference swap amount used when fetching aggregator quotes.",
        20,
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
    const arm = new ethers.Contract(mainnet.etherfiARM, etherFiARMAbi, signer);

    log.info("Setting prices for EtherFi ARM");
    await setPricesForBases({
      setPrices,
      bases: ["EETH", "WEETH"],
      options: {
        signer,
        arm,
        armName: "EtherFi",
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
        priceOffset: true,
        blockTag: "latest",
      },
    });
  },
});
