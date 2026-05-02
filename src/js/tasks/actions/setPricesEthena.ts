import { ethers } from "ethers";

import { action } from "../lib/action";
import { setPrices } from "../armPrices";
import { mainnet } from "../../utils/addresses";
const ethenaARMAbi = require("../../../abis/EthenaARM.json");

action({
  name: "setPricesEthena",
  description: "Set prices for Ethena ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.ethenaARM, ethenaARMAbi, signer);

    log.info("Setting prices for Ethena ARM");
    await setPrices({
      signer,
      arm,
      maxSellPrice: 0.99999,
      minSellPrice: 0.99996,
      maxBuyPrice: 0.9998,
      minBuyPrice: 0.995,
      kyber: true,
      amount: 2000,
      tolerance: 0.1,
      fee: 1,
      offset: 0.2,
      priceOffset: true,
      blockTag: "latest",
      wrapped: true,
    });
  },
});
