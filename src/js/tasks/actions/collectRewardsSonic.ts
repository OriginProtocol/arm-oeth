import { ethers } from "ethers";

import { action } from "../lib/action";
import { collectRewards } from "../sonicHarvest";
import { sonic } from "../../utils/addresses";
const harvesterAbi = require("../../../abis/SonicHarvester.json");

action({
  name: "collectRewardsSonic",
  description: "Collect rewards from Sonic harvester",
  chains: [146],
  run: async ({ signer, log }) => {
    const harvester = new ethers.Contract(
      sonic.harvester,
      harvesterAbi,
      signer
    );

    log.info("Collecting rewards from Sonic harvester");
    await collectRewards({
      signer,
      harvester,
      strategies: [sonic.siloVarlamoreMarket],
    });

    // TODO do Silo, beS and wOS swaps with FlyTrade
  },
});
