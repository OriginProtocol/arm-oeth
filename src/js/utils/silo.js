const { formatUnits, parseUnits } = require("ethers");
const fetch = require("node-fetch");

const log = require("../utils/logger")("utils:silo");

/**
 * Get the current APY from the ARM's active lending market
 */
const getLendingMarketAPY = async (siloMarketWrapper) => {
  if (!siloMarketWrapper) {
    log("No active lending market found, using default APY of 0%");
    return 0n;
  }
  // Get the underlying Silo market address
  const underlyingSiloMarket = await siloMarketWrapper.market();

  // TODO: Make sure it can work for non-Silo markets later
  const response = await fetch(
    `https://v2.silo.finance/api/detailed-vault/sonic-${underlyingSiloMarket}`,
  );
  const data = await response.json();

  // APR scaled to 1e6
  const apr = Number((1000000n * BigInt(data.supplyApr)) / BigInt(1e18));
  log(
    `Current lending APR: ${Number(formatUnits(100n * BigInt(apr), 6)).toFixed(4)}%`,
  );

  const dailyRate = apr / 365 / 1000000;
  const apy = Math.pow(1 + dailyRate, 365) - 1;

  // Scale back to 18 decimals
  return parseUnits(apy.toString(), 18);
};

module.exports = {
  getLendingMarketAPY,
};
