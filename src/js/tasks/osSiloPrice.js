const { formatUnits, parseUnits } = require("ethers");

const addresses = require("../utils/addresses");

const { logTxDetails } = require("../utils/txLogger");

const fetch = require("node-fetch");

const log = console.log; // require("../utils/logger")("task:osSiloPrice");

const setOSSiloPrice = async (options) => {
    const {
        signer,
        arm,
        siloMarketWrapper,
        execute = false
    } = options;

    log("Computing optimal price...");

    // 1. Get current ARM sell price
    const currentSellPrice = parseUnits("1", 72) / (await arm.traderate0());
    const currentBuyPrice = await arm.traderate1();
    log(`Current sell price: ${formatUnits(currentSellPrice, 36)}`);
    log(`Current buy price: ${formatUnits(currentBuyPrice, 36)}`);

    // 2. Get current APY from lending markets
    const currentApyLending = await getLendingMarketAPY(siloMarketWrapper);
    log(`Current lending APY: ${Number(formatUnits(100n * BigInt(currentApyLending), 18)).toFixed(4)}%`);

    // 3. Get current pricing from aggregators
    const testAmountIn = parseUnits("1000", 18);
    const currentPricing = await getFlyTradePrice(testAmountIn, signer);
    log(`Current market pricing: ${Number(formatUnits(currentPricing, 18)).toFixed(4)}`);

    // 4. Calculate highest buy price, we should always target a price lower than this to maintain the APY
    await estimateAverageWithdrawTime(arm);
    //const duration = await calculateAveragePeriod(arm);
    const minBuyingPrice = calculateMinBuyingPrice(currentApyLending, 86400n);
    log(`Calculated highest buying price to maintain APY: ${Number(formatUnits(minBuyingPrice, 36)).toFixed(4)}`);

    // 5. Calculate maxBuyingPrice, market price with an added premium
    const maxBuyingPrice = calculateMaxBuyingPrice(currentPricing, minBuyingPrice);
    log(`Calculated max buying price (market price + premium): ${Number(formatUnits(maxBuyingPrice, 36)).toFixed(4)}`);

    // 6. Set the prices on the ARM contract
    const targetBuyPrice = maxBuyingPrice;
    const targetSellPrice = parseUnits("1", 36); // Keep current sell price for now

    log(`New buy price: ${formatUnits(targetBuyPrice, 36)}`);
    log(`New sell price: ${formatUnits(targetSellPrice, 36)}`);

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

    // Get the underlying Silo market address
    const underlyingSiloMarket = await siloMarketWrapper.market();

    // TODO: Make sure it can work for non-Silo markets later
    const response = await fetch(`https://v2.silo.finance/api/detailed-vault/sonic-${underlyingSiloMarket}`);
    const data = await response.json();

    // APR scaled to 1e6
    const apr = Number((1000000n * BigInt(data.supplyApr)) / BigInt(1e18));
    log(`Current lending APR: ${Number(formatUnits(100n * BigInt(apr), 6)).toFixed(4)}%`);

    const dailyRate = apr / 365 / 1000000;
    const apy = Math.pow(1 + dailyRate, 365) - 1;

    // Scale back to 18 decimals
    return parseUnits(apy.toString(), 18);
};

/**
 * Fetches the price from fly.trade
 */
const getFlyTradePrice = async (amountIn, signer) => {
    log(`Getting price quote from fly.trade...`)

    const urlQuery = [
        `network=sonic`,
        `fromTokenAddress=${addresses.sonic.WS}`,
        `toTokenAddress=${addresses.sonic.OSonicProxy}`,
        `sellAmount=${amountIn}`,
        `fromAddress=${signer.address}`,
        `toAddress=${signer.address}`,
        `slippage=0.005`, // 0.05%
        `gasless=false`
    ].join("&");

    const response = await fetch(`https://api.fly.trade/aggregator/quote?${urlQuery}`, {
        method: "GET",
        headers: {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
        }
    })

    if (!response.ok || response.status !== 200) {
        console.log("Fly.trade response:")
        console.log(response)
        console.log(await response.text())
        throw new Error(`Failed to get price quote from fly.trade: ${response.statusText}`);
    }

    const data = await response.json();
    const amountOut = BigInt(data.amountOut)
    const amountOutScaled = (BigInt(parseUnits("1", 18)) * amountOut) / amountIn
    log(`Fly.trade quote for ${formatUnits(amountIn, 18)} wS: ${Number(formatUnits(amountOutScaled, 18)).toFixed(4)} OS`)
    const flyTradePrice = (BigInt(amountIn) * BigInt(parseUnits("1", 18))) / amountOut
    log(`Fly.trade price for 1OS: ${Number(formatUnits(flyTradePrice, 18)).toFixed(4)} wS`)

    return flyTradePrice;
}

/**
 * Calculate minimum buying price based on APY
 *  Formula: 1/(1+apy) ^ (1 / (365 / 15))
 *  Where 15 is the number of days in the holding period
 */
const calculateMinBuyingPrice = (lendingAPY, duration) => {
    // Scale BN to decimal to make calculations easier
    const apyNumber = Number(formatUnits(lendingAPY, 18))

    const daysPeriod = Number(duration) / 86400;
    const exponent = daysPeriod / 365;

    // 1/(1+apy) ^ (1 / (365 / 15))
    const minPrice = 1 / Math.pow(1 + apyNumber, exponent);

    // Convert back to 36 decimals for ARM pricing
    const minPriceScaled = parseUnits(minPrice.toString(), 36);

    // Ensure we don't go below a reasonable minimum (0.99)
    const minAllowed = parseUnits("0.99", 36);
    return minPriceScaled > minAllowed ? minPriceScaled : minAllowed;
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
const estimateAverageWithdrawTime = async (arm) => {
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    /// --- Fetching wS holding from OS Vault
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    log("\nFetching WS data from OS Vault ...");
    let wSAvailable = 0n;
    const wSAddress = await arm.token0();
    const wS = await hre.ethers.getContractAt(
        ["function balanceOf(address owner) external view returns (uint256)"],
        wSAddress
    );
    wSAvailable += await wS.balanceOf(await arm.vault());
    log(`ws balanceOf OSVault    : ${wSAvailable / parseUnits("1", 18)}`);

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    /// --- Fetching data from OS Vault
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    const vaultAddress = await arm.vault();
    const vault = await hre.ethers.getContractAt(
        [
            "function withdrawalQueueMetadata() external view returns (uint128,uint128,uint128,uint128)",
            "function withdrawalRequests(uint256) external view returns (address,bool,uint40,uint128,uint128)"
        ],
        vaultAddress
    );
    const vaultQueuedWithdrawals = await vault.withdrawalQueueMetadata();
    wSAvailable += vaultQueuedWithdrawals[2] - vaultQueuedWithdrawals[0]; // += claimed amount - queued amount
    log(`Vault Queued amount     : ${vaultQueuedWithdrawals[0] / parseUnits("1", 18)}`);
    log(`Vault Claimed amount    : ${vaultQueuedWithdrawals[2] / parseUnits("1", 18)}`);
    log(`Vault Outstanding amount: ${(vaultQueuedWithdrawals[0] - vaultQueuedWithdrawals[2]) / parseUnits("1", 18)}`);
    log(`Available wS in Vault   : ${wSAvailable / parseUnits("1", 18)}`);

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    /// --- Fetching oS holding from ARM
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    log("\nFetching OS data from ARM ...");
    const oSAddress = await arm.token1();
    const oS = await hre.ethers.getContractAt(
        ["function balanceOf(address owner) external view returns (uint256)"],
        oSAddress
    );

    let oSBalanceInARM = await oS.balanceOf(arm.target);
    log(`os balanceOf ARM        : ${oSBalanceInARM / parseUnits("1", 18)}`);

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    /// --- Fetching data from ARM
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    // This can be replaced with `getReserves()` once the function is added to the ARM contract
    const armWithdrawsQueued = await arm.withdrawsQueued();
    const armWithdrawsClaimed = await arm.withdrawsClaimed();
    const armOutstandingWithdrawals = armWithdrawsQueued - armWithdrawsClaimed;
    const oSAvailable = armOutstandingWithdrawals > oSBalanceInARM ? 0n : oSBalanceInARM - armOutstandingWithdrawals;
    log(`ARM Withdraws queued    : ${armWithdrawsQueued / parseUnits("1", 18)}`);
    log(`ARM Withdraws claimed   : ${armWithdrawsClaimed / parseUnits("1", 18)}`);
    log(`ARM Outstanding Withdraw: ${armOutstandingWithdrawals / parseUnits("1", 18)}`);
    log(`Available OS in ARM     : ${oSAvailable / parseUnits("1", 18)}\n`);

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    /// --- 1. There is more wS in Vault are available than OS in ARM
    /// --- Withdrawal time estimated to be close from: 1 day
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    if (wSAvailable >= oSAvailable) {
        log("More wS available in Vault than OS in ARM, withdrawal time estimated to be close from: 1 day\n");
        return 86400n;
    }

    // If wSAvailable < oSAvailable, we need to fetch from undelegating requests
    const amount = oSAvailable - wSAvailable;
    log(`Amount to fetch from undelegating requests: ${amount}`);

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    /// --- Fetching latests withdrawRequests from OS Vault
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    const numberOfRecentRequests = 50;
    const recentWithdrawalRequests = await Promise.all(
        Array.from({ length: numberOfRecentRequests }, (_, i) =>
            vault.withdrawalRequests(totalWithdrawalsCount[3].toString() - 1 - i)
        )
    );

    // Filter request that have been already claimed
    const unclaimedRequests = recentWithdrawalRequests.filter(req => !req[1]);
    log("Unclaimed request count:", unclaimedRequests.length);

    // Filter request that are older than 13 days
    const oldRequests = unclaimedRequests.filter(req => (Date.now() / 1000 - req[2]) >= 13 * 86400);
    log("Unclaimed request older than 13 days count:", oldRequests.length);
    // Sum the amount of all request that are 13 days older or more
    let sumOfOldRequest = 0n;
    for (const req of oldRequests) {
        sumOfOldRequest += req[3];
    }
    log("Total amount of old requests:", sumOfOldRequest / parseUnits("1", 18));

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    /// --- 2. There is enough old requests to cover the amount needed
    /// --- Withdrawal time estimated to be close from: 1 day
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    if (sumOfOldRequest > amount) return 86400n;

    // Reduce amount by the sum of old requests
    amount -= sumOfOldRequest;
    log("Amount remaining after old requests:", amount / parseUnits("1", 18));

    // Filter request that are younger than 13 days (and not claimed)
    const recentRequests = unclaimedRequests.filter(req => (Date.now() / 1000 - req[2]) < 13 * 86400);
    log("Unclaimed request younger than 13 days count:", recentRequests.length);
    let totalWeightedTime = 0n;
    let totalAmount = 0n;
    // Calculate the total weighted time and amount for recent requests
    for (const req of recentRequests) {
        const weight = (13 * 86400 - (Date.now() / 1000 - req[2]));
        totalWeightedTime += weight * req[3];
        totalAmount += req[3];
        amount -= req[3];
        if (amount <= 0) break;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    /// --- 3. There is not enough recent requests to cover the amount needed
    /// --- Withdrawal time estimated to be close from: 14 days (maximal)
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    if (amount > 0) return 14n * 86400n; // We didn't find enough recent requests to cover the amount

    // If we reach this point, it means we found enough recent requests to use average weighted time
    log("Total weighted time (only < 13 days):", totalWeightedTime);
    log("Total amount (only < 13 days):", totalAmount / parseUnits("1", 18));

    totalWeightedTime += sumOfOldRequest * 86400n;
    totalAmount += sumOfOldRequest;

    log("Total weighted time (including old requests):", totalWeightedTime);
    log("Total amount (including old requests):", totalAmount / parseUnits("1", 18));

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    /// --- 4. There is enough recent requests to cover the amount needed
    /// --- Withdrawal time calculated using average weighted time: between 1 day and 14 days
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    log(
        "Estimated withdrawal time in days and hours:",
        (totalWeightedTime / totalAmount) / BigInt(86400),
        "days",
        (totalWeightedTime / totalAmount) % BigInt(86400) / BigInt(3600),
        "hours"
    );
    return totalWeightedTime / totalAmount;
}

const calculateAveragePeriod = async (arm) => {
    // Get OS Vault
    const vaultAddress = await arm.vault();
    const vault = await hre.ethers.getContractAt(
        [
            "function withdrawalQueueMetadata() external view returns (uint128,uint128,uint128,uint128)",
            "function withdrawalRequests(uint256) external view returns (address,bool,uint40,uint128,uint128)"
        ],
        vaultAddress
    );

    // Get total withdrawal count
    const totalWithdrawalsCount = await vault.withdrawalQueueMetadata();
    log(`Total request withdrawals: ${totalWithdrawalsCount[3]}`);

    // Fetch last x withdrawal requests
    const numberOfRecentRequests = 50;
    const recentWithdrawalRequests = await Promise.all(
        Array.from({ length: numberOfRecentRequests }, (_, i) =>
            vault.withdrawalRequests(totalWithdrawalsCount[3].toString() - 1 - i)
        )
    );

    // Filter recentWithdrawalRequests to keep only those where [1] is false (not claimed) and < 14 days old
    const currentTimestamp = BigInt(Math.floor(Date.now() / 1000));
    const fourteenDaysInSeconds = BigInt(14 * 24 * 60 * 60);
    const filteredWithdrawalRequests = recentWithdrawalRequests.filter(request =>
        !request[1] && ((currentTimestamp - request[2]) <= fourteenDaysInSeconds)
    );
    log("Filtered withdrawal requests count:", filteredWithdrawalRequests.length);

    // Calculate the weighted average period
    let totalWeightedTime = BigInt(0);
    let totalAmount = BigInt(0);
    for (const request of filteredWithdrawalRequests) {
        const timeRemaining = fourteenDaysInSeconds - (currentTimestamp - request[2]);
        const amount = BigInt(request[3]);

        totalWeightedTime += timeRemaining * amount;
        totalAmount += amount;
    }

    const weightedAveragePeriod = totalAmount > 0 ? totalWeightedTime / totalAmount : BigInt(0);
    log(
        "Total amount (in ether):",
        (totalAmount / parseUnits("1", 18)).toString()
    );
    log(
        "Weighted average period:",
        (weightedAveragePeriod / BigInt(86400)).toString(),
        "days",
        (weightedAveragePeriod % BigInt(86400) / BigInt(3600)).toString(),
        "hours"
    );

    return weightedAveragePeriod;
};

const calculateMaxBuyingPrice = (marketPrice, minBuyingPrice) => {
    // Scale market price to 36 decimals for ARM pricing
    const marketPriceScaled = marketPrice * parseUnits("1", 18);

    // Add a small premium to market price (0.1 basis points = 0.001%)
    const premium = marketPriceScaled * 1n / 100000n; // 0.001%
    const maxPrice = marketPriceScaled + premium;

    // Ensure it doesn't exceed the minimum buying price
    // The max buying price must be below minBuyingPrice to maintain profitability
    return maxPrice < minBuyingPrice ? maxPrice : minBuyingPrice;
};

module.exports = {
    setOSSiloPrice,
};
