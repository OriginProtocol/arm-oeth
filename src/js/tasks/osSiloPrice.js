const { formatUnits, parseUnits } = require("ethers");

const { abs } = require("../utils/maths");
const { getLendingMarketAPY } = require("../utils/silo");
const {
  outstandingValidatorWithdrawalRequests,
} = require("../utils/osStaking");
const addresses = require("../utils/addresses");
const { flyTradeQuote } = require("../utils/fly");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:osSiloPrice");

const setOSSiloPrice = async (options) => {
  const {
    signer,
    arm,
    siloMarketWrapper,
    execute = false,
    wS,
    oS,
    vault,
    marketPremium: marketPremiumBP = 0.3, // 0.003%
    lendPremium: lendPremiumBP = 0.3, // 0.003%
    tolerance = 0.1, // 0.0001%
    blockTag,
  } = options;

  log("Computing optimal price...");

  // 1. Get current ARM sell price
  const currentSellPrice = parseUnits("1", 72) / (await arm.traderate0());
  const currentBuyPrice = await arm.traderate1();
  log(
    `Current sell price  : ${Number(formatUnits(currentSellPrice, 36)).toFixed(5)}`,
  );
  log(
    `Current buy price   : ${Number(formatUnits(currentBuyPrice, 36)).toFixed(5)}`,
  );

  // 2. Get current APY from lending markets
  const currentApyLending = await getLendingMarketAPY(siloMarketWrapper);
  log(
    `Current lending APY : ${Number(formatUnits(100n * BigInt(currentApyLending), 18)).toFixed(4)}%`,
  );

  // 3. Calculate the max OS buy price that maintains the current lending market APY

  // Estimate the average withdrawal time from the OS Vault in seconds
  const withdrawalTimeInSeconds = await estimateAverageWithdrawTime(
    arm,
    blockTag,
    signer,
    wS,
    oS,
    vault,
  );
  const buyPriceFromLendingRate = calculateBuyPriceFromLendingRate(
    currentApyLending,
    lendPremiumBP,
    withdrawalTimeInSeconds,
  );
  log(
    `premium on lending market APY                 : ${lendPremiumBP} basis points`,
  );
  log(
    `buy price from lending market with premium    : ${Number(formatUnits(buyPriceFromLendingRate, 36)).toFixed(5)}`,
  );

  // 4. Get current pricing from aggregators
  const testAmountIn = parseUnits("1000", 18);

  const { price: marketBuyPrice } = await flyTradeQuote({
    from: addresses.sonic.WS,
    to: addresses.sonic.OSonicProxy,
    amount: testAmountIn,
    slippage: 0.005, // 0.5%
    swapper: await signer.getAddress(),
    recipient: await signer.getAddress(),
    getData: false,
  });
  log(
    `Current Fly market buy price                  : ${Number(formatUnits(marketBuyPrice, 18)).toFixed(5)}`,
  );

  // Add the premium to market price
  const marketPriceScaled = marketBuyPrice * parseUnits("1", 18);
  const marketPriceWithPremium =
    marketPriceScaled + parseUnits(marketPremiumBP.toString(), 36 - 4);
  log(
    `Market buy price with ${marketPremiumBP} basis point premium : ${Number(formatUnits(marketPriceWithPremium, 36)).toFixed(5)}`,
  );

  // 5. Calculate targetBuyPrice, which is the smaller of the market buy price with added premium or buy price from lending rate
  const targetBuyPrice = calculateMinBuyingPrice(
    marketPriceWithPremium,
    buyPriceFromLendingRate,
  );
  log(
    `Calculated buy price                          : ${Number(formatUnits(targetBuyPrice, 36)).toFixed(5)}`,
  );

  // 6. Set the prices on the ARM contract
  const targetSellPrice = parseUnits("1", 36); // Keep current sell price for now

  // 7. Check the price difference is above the tolerance level
  const diffBuyPrice = abs(targetBuyPrice - currentBuyPrice);
  log(`buy price diff     : ${formatUnits(diffBuyPrice, 32)} basis points`);

  // tolerance option is in basis points
  const toleranceScaled = parseUnits(tolerance.toString(), 36 - 4);
  log(`tolerance          : ${formatUnits(toleranceScaled, 32)} basis points`);

  // decide if rates need to be updated
  if (diffBuyPrice < toleranceScaled) {
    console.log(
      `No price update as price diff of buy ${formatUnits(
        diffBuyPrice,
        32,
      )} < tolerance ${formatUnits(toleranceScaled, 32)} basis points`,
    );
    return;
  }

  if (execute) {
    if (blockTag !== "latest") {
      throw new Error("Cannot execute price update on historical block");
    }

    log("Updating ARM prices...");
    const tx = await arm
      .connect(signer)
      .setPrices(targetBuyPrice.toString(), targetSellPrice.toString());

    await logTxDetails(tx, "setOSSiloPrice");
  }
};

/**
 * Calculate buying price based on APY
 *  Formula: 1/(1+apy) ^ (daysPeriod / 365)
 *  Where 15 is the number of days in the holding period
 * @param {BigInt} lendingAPY - The current APY from the lending market (in 18 decimals)
 * @param {number} lendPremiumBP - Basis points to add to the lending rate. eg 0.3 = 0.003%
 * @param {BigInt} withdrawalTimeInSeconds - Estimated average withdrawal time in seconds
 * @returns {BigInt} - The calculated buy price (in 36 decimals)
 */
const calculateBuyPriceFromLendingRate = (
  lendingAPY,
  lendPremiumBP,
  withdrawalTimeInSeconds,
) => {
  // Scale BN to decimal to make calculations easier
  const apyNumber = Number(formatUnits(lendingAPY, 18));

  const daysPeriod = Number(withdrawalTimeInSeconds) / 86400;
  const exponent = daysPeriod / 365;

  // 1/(1+apy) ^ (daysPeriod / 365)
  const price = 1 / Math.pow(1 + apyNumber, exponent);

  // Convert back to 36 decimals for ARM pricing
  const priceScaled = parseUnits(price.toString(), 36);
  log(
    `buy price from lending market                 : ${Number(formatUnits(priceScaled, 36)).toFixed(5)}`,
  );

  const priceWithPremium =
    priceScaled + parseUnits(lendPremiumBP.toString(), 36 - 4);

  // Ensure we don't go below a reasonable minimum (0.99)
  // 1% over 14 days is roughly 26 APY
  const floorBuyPrice = parseUnits("0.99", 36);

  return priceWithPremium > floorBuyPrice ? priceWithPremium : floorBuyPrice;
};

const calculateMinBuyingPrice = (marketPrice, buyPriceFromLendingRate) => {
  // The buy price from the market price must be below the buy price from the lending market to maintain profitability
  return marketPrice < buyPriceFromLendingRate
    ? marketPrice
    : buyPriceFromLendingRate;
};

/**
 * @notice Estimates the average withdrawal time for a given ARM contract.
 * @dev This function calculates the estimated withdrawal time based on the availability of tokens
 *      in the OS Vault and ARM contract, as well as the status of withdrawal requests.
 *
 * Scenarios:
 * 1. If there is more wS available in the OS Vault than oS in the ARM contract, the withdrawal time
 *    is estimated to be close to 1 day.
 * 2. If there are enough unclaimed withdrawal requests older than 13 days to cover the required amount,
 *    the withdrawal time is estimated to be close to 1 day.
 * 3. If there are not enough unclaimed withdrawal requests (both older and younger than 13 days) to cover
 *    the required amount, the withdrawal time is estimated to be the maximum of 14 days.
 * 4. If there are enough unclaimed withdrawal requests (including recent ones) to cover the required amount,
 *    the withdrawal time is calculated using a weighted average based on the age of the requests.
 */
const estimateAverageWithdrawTime = async (
  arm,
  blockTag,
  signer,
  wS,
  oS,
  vault,
) => {
  const { timestamp, number: blockNumber } =
    await signer.provider.getBlock(blockTag);
  log(`Using block number ${blockNumber} at timestamp ${timestamp}`);

  // Check if the ARM contract exist at this block
  const code = await signer.provider.getCode(arm.target, blockTag);
  if (code === "0x") {
    throw new Error(`ARM contract does not exist at block ${blockTag}`);
  }

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  /// --- Fetching wS holding from OS Vault
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  log(`\nFetching wS balance from OS Vault ...`);
  let wSAvailableInVault = 0n;
  wSAvailableInVault += await wS.balanceOf(vault.target, { blockTag });
  log(`wS balanceOf OS Vault    : ${formatUnits(wSAvailableInVault, 18)}`);

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  /// --- Fetching data from OS Vault
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  const vaultQueuedWithdrawals = await vault.withdrawalQueueMetadata({
    blockTag,
  });
  wSAvailableInVault += vaultQueuedWithdrawals[2] - vaultQueuedWithdrawals[0]; // += claimed amount - queued amount
  log(
    `Vault Queued amount      : ${formatUnits(vaultQueuedWithdrawals[0], 18)}`,
  );
  log(
    `Vault Claimed amount     : ${formatUnits(vaultQueuedWithdrawals[2], 18)}`,
  );
  log(
    `Vault withdraw shortfall : ${formatUnits(vaultQueuedWithdrawals[0] - vaultQueuedWithdrawals[2], 18)}`,
  );
  log(`Vault wS available       : ${formatUnits(wSAvailableInVault, 18)}`);

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  /// --- Fetching OS and wS holdings from ARM
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  log(`\nFetching wS and OS balances from ARM ...`);
  let wSBalanceInARM = await wS.balanceOf(arm.target, { blockTag });
  log(`wS balanceOf ARM         : ${formatUnits(wSBalanceInARM, 18)}`);
  let oSBalanceInARM = await oS.balanceOf(arm.target, { blockTag });
  log(`OS balanceOf ARM         : ${formatUnits(oSBalanceInARM, 18)}`);

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  /// --- Fetching data from ARM
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // This can be replaced with `getReserves()` once the function is added to the ARM contract
  const armWithdrawsQueued = await arm.withdrawsQueued({ blockTag });
  const armWithdrawsClaimed = await arm.withdrawsClaimed({ blockTag });
  const armOutstandingWithdrawals = armWithdrawsQueued - armWithdrawsClaimed;
  const wSAvailableInARM = wSBalanceInARM - armOutstandingWithdrawals;
  log(`ARM Withdraws queued     : ${formatUnits(armWithdrawsQueued, 18)}`);
  log(`ARM Withdraws claimed    : ${formatUnits(armWithdrawsClaimed, 18)}`);
  log(
    `ARM Outstanding Withdraw : ${formatUnits(armOutstandingWithdrawals, 18)}`,
  );
  log(`wS Available in ARM      : ${formatUnits(wSAvailableInARM, 18)}`);

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  /// --- 1. There is more wS available in the Vault than wS and OS in the ARM,
  // then no need to loop at staking strategy validator withdrawals.
  /// --- Withdrawal time estimated at 1 day
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  if (wSBalanceInARM + oSBalanceInARM <= wSAvailableInVault) {
    log(
      `More wS available in Vault than liquidity in ARM, withdrawal time estimated 1 day\n`,
    );
    return 86400n;
  }

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  /// --- Fetching outstanding undelegate requests from OS Vault's staking strategy
  ////////////////////////////////////////////////////////////////////////////////////////////////////

  // Current UTC timestamp in seconds
  const nowTimestampSec = BigInt(Math.floor(Date.now() / 1000));
  log(`Now timestamp in seconds : ${nowTimestampSec}`);

  const validatorWithdrawalRequests =
    await outstandingValidatorWithdrawalRequests();

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  /// --- Calculate the weighted amount average time remaining in days to withdraw the wS available in the ARM.
  ////////////////////////////////////////////////////////////////////////////////////////////////////

  // Iterate through requests starting from the oldest to the newest
  let totalValidatorWithdrawalAmount = 0n;
  let totalArmWithdrawalAmount = 0n;
  let totalArmWithdrawalAmountPrevious = 0n;
  let totalAmountAndRemainingTime = 0n;
  for (const req of validatorWithdrawalRequests) {
    log(
      `  - ${req.wrID} id ${formatUnits(BigInt(req.amount), 18)} S requested at ${req.createdAt}`,
    );

    totalValidatorWithdrawalAmount += BigInt(req.amount);
    totalArmWithdrawalAmountPrevious = totalArmWithdrawalAmount;

    if (totalValidatorWithdrawalAmount < oSBalanceInARM - wSAvailableInVault) {
      // Have not cleared the OS Vault's outstanding withdrawals and the OS in the ARM.
      // Keep iterating until we have.
      continue;
    } else if (totalArmWithdrawalAmount === 0n) {
      log(`    Cleared outstanding OS Vault withdrawals and OS in ARM. `);
      totalArmWithdrawalAmount +=
        totalValidatorWithdrawalAmount - (oSBalanceInARM - wSAvailableInVault);
    } else {
      totalArmWithdrawalAmount += BigInt(req.amount);
    }
    log(
      `    Total ARM withdrawal amount: ${formatUnits(totalArmWithdrawalAmount, 18)}`,
    );

    // validator withdrawal request timestamp in seconds
    const requestCreatedTimestampMs = new Date(req.createdAt).getTime();
    const requestCreatedTimestampSec = BigInt(
      Math.floor(requestCreatedTimestampMs / 1000),
    );
    // claimable timestamp in seconds which is 14 days after the request was created
    const requestClaimableTimestampSec =
      requestCreatedTimestampSec + 14n * 86400n;
    // If the request is already claimable, the remaining time is 0 rather than negative
    const secondsToClaimable =
      requestClaimableTimestampSec > nowTimestampSec
        ? requestClaimableTimestampSec - nowTimestampSec
        : 0n;

    log(
      `    Time to claimable: ${secondsToClaimable} seconds, ${(Number(secondsToClaimable) / 86400).toFixed(2)} days`,
    );

    // If there is more than enough validator withdrawal requests to cover the wS available in the ARM
    if (totalArmWithdrawalAmount > wSAvailableInARM) {
      // As we have gone over what's required, work out the remaining amount for the weighted average calculation
      const remainingAmount =
        wSAvailableInARM - totalArmWithdrawalAmountPrevious;
      log(
        `    Remaining amount to cover wS available in the ARM: ${formatUnits(remainingAmount, 18)}`,
      );
      totalAmountAndRemainingTime +=
        remainingAmount * BigInt(secondsToClaimable);

      // No need to loop further
      break;
    }

    // Add to the weighted average calculation
    totalAmountAndRemainingTime +=
      BigInt(req.amount) * BigInt(secondsToClaimable);
    log(
      `    Total weighted amount: ${formatUnits(totalAmountAndRemainingTime, 18)}`,
    );
  }

  // If there was not enough validator withdrawal requests to cover the wS available to swap in the ARM
  if (totalArmWithdrawalAmount < wSAvailableInARM) {
    // Assume a new request for the remaining amount will take the maximum time of 14 days
    totalAmountAndRemainingTime +=
      (wSAvailableInARM - totalArmWithdrawalAmount) * 14n * 86400n;
    log(
      `Not enough validator withdrawal requests to cover the wS available in ARM, assuming new request for remaining ${formatUnits(wSAvailableInARM - totalArmWithdrawalAmount, 18)} S will take 14 days`,
    );
  }

  const amountWeightedAverageSeconds =
    totalAmountAndRemainingTime / wSAvailableInARM;
  const amountWeightedAverageDays =
    Number(amountWeightedAverageSeconds) / 86400;

  log(
    `Amount weighted average time : ${amountWeightedAverageDays.toFixed(2)} days\n`,
  );

  return amountWeightedAverageSeconds;
};

module.exports = {
  setOSSiloPrice,
};
