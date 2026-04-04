import { ethers } from "ethers";

import { action } from "../lib/action";
import { setPrices } from "../armPrices";
import { mainnet } from "../../utils/addresses";
const etherFiARMAbi = require("../../../abis/EtherFiARM.json");

action({
  name: "setPricesEtherFi",
  description: "Set prices for EtherFi ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.etherfiARM, etherFiARMAbi, signer);

    log.info("Setting prices for EtherFi ARM");
    await setPrices({
      signer,
      arm,
      maxSellPrice: 1.0,
      minSellPrice: 0.99996,
      maxBuyPrice: 0.9996,
      minBuyPrice: 0.9985,
      kyber: true,
      amount: 10,
      tolerance: 0.2,
      fee: 0.5,
      offset: 0.3,
      priceOffset: true,
      blockTag: "latest",
    });
  },
});
