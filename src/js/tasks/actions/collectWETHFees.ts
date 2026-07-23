import { ethers } from "ethers";

import { action } from "../lib/action";
import { collectFees } from "../admin";
import { mainnet } from "../../utils/addresses";
const multiAssetARMAbi = require("../../../abis/MultiAssetARM.json");

action({
  name: "collectWETHFees",
  description: "Collect fees from WETH ARM",
  chains: [1],
  run: async ({ signer, log }) => {
    const arm = new ethers.Contract(mainnet.wethARM, multiAssetARMAbi, signer);

    log.info("Collecting fees from WETH ARM");
    await collectFees({ signer, arm });
  },
});
