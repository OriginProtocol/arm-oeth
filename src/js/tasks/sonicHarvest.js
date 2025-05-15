const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:admin");

async function collectRewards({ siloMarket, signer }) {
  log(`About to collect Silo Rewards`);
  const tx = await siloMarket.connect(signer).collectRewards();
  await logTxDetails(tx, "collectRewards");
}

module.exports = {
  collectRewards,
};
