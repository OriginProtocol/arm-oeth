import { ethers } from "ethers";

import { action } from "../lib/action";
import { collectFees } from "../admin";
import { mainnet } from "../../utils/addresses";
const multiAssetARMAbi = require("../../../abis/MultiAssetARM.json");

action({
  name: "collectUSDFees",
  description: "Collect fees from USD ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.usdARM, multiAssetARMAbi, signer);

    log.info("Collecting fees from USD ARM");
    await collectFees({ signer, arm, decimals: 6 });
  },
});
