import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { setPrices } from "../armPrices";
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
      ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.etherfiARM, armAbi, signer);

    log.info("Setting prices for OETH ARM");
    await setPrices({
      signer,
      arm,
      maxSellPrice: args.maxSellPrice,
      minSellPrice: args.minSellPrice,
      maxBuyPrice: args.maxBuyPrice,
      minBuyPrice: args.minBuyPrice,
      kyber: true,
      amount: 10,
      tolerance: 0.3,
      fee: 5,
      offset: 1.0,
      priceOffset: true,
      blockTag: "latest",
    });
  },
});
