import { ethers } from "ethers";

import { action } from "../lib/action";
import { pauseARM } from "../admin";
import { mainnet } from "../../utils/addresses";
const multiAssetARMAbi = require("../../../abis/MultiAssetARM.json");

action({
  name: "pauseUSD",
  description: "Pause the USD ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.usdARM, multiAssetARMAbi, signer);

    log.info("Pausing the USD ARM");
    await pauseARM({ signer, arm });
  },
});
