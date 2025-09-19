const { formatUnits } = require("ethers");

const { resolveAsset } = require("../utils/assets");
const { logTxDetails } = require("../utils/txLogger");
const { flyTradeQuote } = require("../utils/magpie");

const log = require("../utils/logger")("task:sonic:harvest");

async function collectRewards({ harvester, strategies, signer }) {
  log(`About to collect rewards from the following strategies: ${strategies}`);
  const tx = await harvester.connect(signer).collect(strategies);
  await logTxDetails(tx, "collect");
}

async function harvestRewards({ harvester, signer, symbol }) {
  const rewardToken = await resolveAsset(symbol.toUpperCase());
  const rewards = await rewardToken.balanceOf(harvester.getAddress());

  if (rewards == 0n) {
    console.log("No token rewards to harvest");
    return;
  }

  const { data: flyTradeData, fees: flyTradeFees } = await flyTradeQuote({
    from: symbol.toUpperCase(),
    to: "WS",
    amount: rewards,
    slippage: 0.5,
    swapper: await harvester.getAddress(),
    recipient: await harvester.getAddress(),
  });

  log(
    `About to harvest ${formatUnits(rewards)} ${symbol} rewards using FlyTrade`,
  );
  // At the moment the harvester fix has not been deployed yet on sonic.
  // When it will be done, uncomment the flyTradeFees on the swap function just below.
  const tx = await harvester
    .connect(signer)
    .swap(
      0,
      await rewardToken.getAddress(),
      rewards /*, flyTradeFees*/,
      flyTradeData,
    );
  await logTxDetails(tx, "swap rewards");
}

async function setHarvester({ siloMarket, harvester, signer }) {
  log(`About to set the harvester to ${harvester}`);
  const tx = await siloMarket.connect(signer).setHarvester(harvester);
  await logTxDetails(tx, "setHarvester");
}

module.exports = {
  collectRewards,
  harvestRewards,
  setHarvester,
};
