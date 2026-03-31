import { ethers } from "ethers";

import { action } from "../lib/action";
import { setPrices } from "../armPrices";
import { mainnet } from "../../utils/addresses";
const armAbi = require("../../../abis/OriginARM.json");

action({
  name: "setPricesOETH",
  description: "Set prices for OETH ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.etherfiARM, armAbi, signer);

    log.info("Setting prices for OETH ARM");
    await setPrices({
      signer,
      arm,
      maxSellPrice: 0.9999,
      minSellPrice: 0.9995,
      maxBuyPrice: 0.9995,
      minBuyPrice: 0.996,
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
