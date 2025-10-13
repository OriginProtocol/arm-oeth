const { formatUnits, parseUnits } = require("ethers");
const fetch = require("node-fetch");

const log = require("../utils/logger")("utils:silo");

/**
 * Get the current lending rate from the ARM's active lending market and add a premium
 * @param {Object} siloMarketWrapper - The SiloMarketWrapper contract instance
 * @param {number} lendPremiumBP - Basis points to add to the annual rate. eg 0.3 = 0.003%
 * @return {BigInt} The annual lending rate scaled to 18 decimals
 */
const getLendingMarketRate = async (siloMarketWrapper, lendPremiumBP) => {
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

  // Annual rate scaled to 1e6
  // This is a rate and not a percentage so 5% = 0.05 = 50000
  const annualRate = Number(
    (BigInt(1e6) * BigInt(data.supplyApr)) / BigInt(1e18),
  );
  log(
    `Current annual lending rate                 : ${Number(formatUnits(100n * BigInt(annualRate), 6)).toFixed(4)}%`,
  );

  // Annual rate with premium
  // Scale the premium from basis points (1e4) to 1e6
  const annualRateWithPremium = annualRate + lendPremiumBP * 100;
  log(
    `Annual lending rate with ${lendPremiumBP
      .toString()
      .padStart(
        4,
      )} bps premium   : ${Number(formatUnits(100n * BigInt(annualRateWithPremium), 6)).toFixed(4)}%`,
  );

  // Daily rate
  const dailyRate = annualRateWithPremium / 365 / 1000000;
  log(
    `Daily lending rate with premium             : ${Number(dailyRate * 10000).toFixed(4)} basis points`,
  );
  // Compounding annual rate
  const compoundingAnnualRate = Math.pow(1 + dailyRate, 365) - 1;

  // Scale back to 18 decimals
  return parseUnits(compoundingAnnualRate.toString(), 18);
};

module.exports = {
  getLendingMarketRate,
};
