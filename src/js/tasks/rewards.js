const { parseDeployedAddress } = require("../utils/addressParser");

const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:rewards");

async function collectMorphoRewards({ arm, signer }) {
  const marketAddress =
    arm === "Lido"
      ? await parseDeployedAddress("MORPHO_MARKET_MEVCAPITAL")
      : arm === "EtherFi"
        ? await parseDeployedAddress("MORPHO_MARKET_ETHERFI")
        : undefined;
  const market = await ethers.getContractAt(
    "MorphoMarket",
    marketAddress,
    signer,
  );

  log(`About to collect rewards from the Morpho market at ${marketAddress}.`);
  const tx = await market.collectRewards();
  await logTxDetails(tx, "collectRewards");
}

module.exports = { collectMorphoRewards };
