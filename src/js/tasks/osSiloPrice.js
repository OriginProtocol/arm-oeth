const { formatUnits, parseUnits } = require("ethers");
const fetch = require("node-fetch");

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
    blockTag,
  } = options;

  log("Computing optimal price...");

  // 1. Get current ARM sell price
  const currentSellPrice = parseUnits("1", 72) / (await arm.traderate0());
  const currentBuyPrice = await arm.traderate1();
  log(`Current sell price: ${formatUnits(currentSellPrice, 36)}`);
  log(`Current buy price: ${formatUnits(currentBuyPrice, 36)}`);

  // 2. Get current APY from lending markets
  const currentApyLending = await getLendingMarketAPY(siloMarketWrapper);
  log(
    `Current lending APY: ${Number(formatUnits(100n * BigInt(currentApyLending), 18)).toFixed(4)}%`,
  );

  // 3. Get current pricing from aggregators
  const testAmountIn = parseUnits("1000", 18);

  const { price: currentPricing4Decimals } = await flyTradeQuote({
    from: addresses.sonic.WS,
    to: addresses.sonic.OSonicProxy,
    amount: testAmountIn,
    slippage: 0.005, // 0.5%
    swapper: await signer.getAddress(),
    recipient: await signer.getAddress(),
    getData: false,
  });
  const currentPricing = parseUnits(currentPricing4Decimals.toString(), 14);
  // log(`Current market pricing: ${Number(currentPricing).toFixed(4)}`);
  log(
    `Current market pricing: ${Number(formatUnits(currentPricing, 18)).toFixed(4)}`,
  );

  // 4. Calculate highest buy price, we should always target a price lower than this to maintain the APY
  const duration = await estimateAverageWithdrawTime(
    arm,
    blockTag,
    signer,
    wS,
    oS,
    vault,
  );
  //const duration = await calculateAveragePeriod(arm);
  const minBuyingPrice = calculateMinBuyingPrice(currentApyLending, duration);
  log(
    `Calculated highest buying price to maintain APY: ${Number(formatUnits(minBuyingPrice, 36)).toFixed(4)}`,
  );

  // 5. Calculate maxBuyingPrice, market price with an added premium
  const maxBuyingPrice = calculateMaxBuyingPrice(
    currentPricing,
    minBuyingPrice,
  );
  log(
    `Calculated max buying price (market price + premium): ${Number(formatUnits(maxBuyingPrice, 36)).toFixed(4)}`,
  );

  // 6. Set the prices on the ARM contract
  const targetBuyPrice = maxBuyingPrice;
  const targetSellPrice = parseUnits("1", 36); // Keep current sell price for now

  log(`New buy price: ${formatUnits(targetBuyPrice, 36)}`);
  log(`New sell price: ${formatUnits(targetSellPrice, 36)}`);

  if (blockTag !== "latest") {
    throw new Error("Cannot execute price update on historical block");
  }

  if (execute) {
    log("Updating ARM prices...");
    const tx = await arm
      .connect(signer)
      .setPrices(targetBuyPrice.toString(), targetSellPrice.toString());

    await logTxDetails(tx, "setOSSiloPrice");
  }
};

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

/**
 * Calculate minimum buying price based on APY
 *  Formula: 1/(1+apy) ^ (daysPeriod / 365)
 *  Where 15 is the number of days in the holding period
 */
const calculateMinBuyingPrice = (lendingAPY, duration) => {
  // Scale BN to decimal to make calculations easier
  const apyNumber = Number(formatUnits(lendingAPY, 18));

  const daysPeriod = Number(duration) / 86400;
  const exponent = daysPeriod / 365;

  // 1/(1+apy) ^ (daysPeriod / 365)
  const minPrice = 1 / Math.pow(1 + apyNumber, exponent);

  // Convert back to 36 decimals for ARM pricing
  const minPriceScaled = parseUnits(minPrice.toString(), 36);

  // Ensure we don't go below a reasonable minimum (0.99)
  const minAllowed = parseUnits("0.99", 36);
  return minPriceScaled > minAllowed ? minPriceScaled : minAllowed;
};

const calculateMaxBuyingPrice = (marketPrice, minBuyingPrice) => {
  // Scale market price to 36 decimals for ARM pricing
  const marketPriceScaled = marketPrice * parseUnits("1", 18);

  // Add a small premium to market price (0.1 basis points = 0.001%)
  const premium = (marketPriceScaled * 1n) / 100000n; // 0.001%
  const maxPrice = marketPriceScaled + premium;

  // Ensure it doesn't exceed the minimum buying price
  // The max buying price must be below minBuyingPrice to maintain profitability
  return maxPrice < minBuyingPrice ? maxPrice : minBuyingPrice;
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

  return amountWeightedAverageDays;
};

module.exports = {
  setOSSiloPrice,
};
