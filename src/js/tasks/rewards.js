const { formatUnits } = require("ethers");
const { parseDeployedAddress } = require("../utils/addressParser");
const { getMerklRewards } = require("../utils/merkl");

const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:rewards");

async function claimMerklRewards(marketVaultAddress, signer) {
  const result = await getMerklRewards({
    userAddress: marketVaultAddress,
    chainId: 1,
  });

  log(
    `${formatUnits(result.amount, 18)} ${result.token} rewards available to claim.`,
  );

  const marketVault = await ethers.getContractAt(
    "Abstract4626MarketWrapper",
    marketVaultAddress,
    signer,
  );

  const tx = await marketVault.merkleClaim(
    result.token,
    result.amount,
    result.proofs,
  );
  await logTxDetails(tx, "merkleClaim");
}

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

module.exports = { claimMerklRewards, collectMorphoRewards };
