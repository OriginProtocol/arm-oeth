const { formatUnits } = require("ethers");

const { resolveAsset } = require("../utils/assets");
const { logTxDetails } = require("../utils/txLogger");
const { magpieQuote } = require("../utils/magpie");

const log = require("../utils/logger")("task:sonic:harvest");

async function collectRewards({ siloMarket, signer }) {
  log(`About to collect Silo Rewards`);
  const tx = await siloMarket.connect(signer).collectRewards();
  await logTxDetails(tx, "collectRewards");
}

async function harvestRewards({ harvester, signer }) {
  const silo = await resolveAsset("SILO");
  const siloRewards = await silo.balanceOf(harvester.getAddress());

  if (siloRewards == 0n) {
    console.log("No Silo rewards to harvest");
    return;
  }

  const { data: magpieData } = await magpieQuote({
    from: "SILO",
    to: "WS",
    amount: siloRewards,
    slippage: 0.5,
    swapper: await harvester.getAddress(),
    recipient: await harvester.getAddress(),
  });

  log(`About to harvest ${formatUnits(siloRewards)} Silo rewards using Magpie`);
  const tx = await harvester
    .connect(signer)
    .swap(0, silo.getAddress(), siloRewards, magpieData);
  await logTxDetails(tx, "swap rewards");
}

module.exports = {
  collectRewards,
  harvestRewards,
};
