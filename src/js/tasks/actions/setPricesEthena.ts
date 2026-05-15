import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { setPrices } from "../armPrices";
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
      ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.ethenaARM, ethenaARMAbi, signer);

    log.info("Setting prices for Ethena ARM");
    await setPrices({
      signer,
      arm,
      maxSellPrice: args.maxSellPrice,
      minSellPrice: args.minSellPrice,
      maxBuyPrice: args.maxBuyPrice,
      minBuyPrice: args.minBuyPrice,
      kyber: true,
      amount: 2000,
      tolerance: 0.09,
      fee: 2,
      offset: 0.2,
      priceOffset: true,
      blockTag: "latest",
      wrapped: true,
    });
  },
});
