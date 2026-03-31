import { ethers } from "ethers";

import { action } from "../lib/action";
import { setPrices } from "../armPrices";
import { mainnet } from "../../utils/addresses";
const lidoARMAbi = require("../../../abis/LidoARM.json");

action({
  name: "setPricesLido",
  description: "Set prices for Lido ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.lidoARM, lidoARMAbi, signer);

    log.info("Setting prices for Lido ARM");
    await setPrices({
      signer,
      arm,
      maxSellPrice: 1.0,
      minSellPrice: 0.9999,
      maxBuyPrice: 0.999,
      minBuyPrice: 0.998,
      kyber: true,
      amount: 100,
      tolerance: 0.1,
      fee: 0.5,
      offset: 0.1,
      priceOffset: true,
      blockTag: "latest",
    });
  },
});
