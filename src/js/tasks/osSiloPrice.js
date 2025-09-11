const { formatUnits, parseUnits } = require("ethers");

const addresses = require("../utils/addresses");

const { logTxDetails } = require("../utils/txLogger");
const { getBlock } = require("../utils/block");


const fetch = require("node-fetch");

const log = console.log; // require("../utils/logger")("task:osSiloPrice");

const setOSSiloPrice = async (options) => {
    const {
        signer,
        arm,
        siloMarketWrapper,
        execute = false,
        block
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
    const duration = await estimateAverageWithdrawTime(arm, block);
    //const duration = await calculateAveragePeriod(arm);
    const minBuyingPrice = calculateMinBuyingPrice(currentApyLending, duration);
    log(`Calculated highest buying price to maintain APY: ${Number(formatUnits(minBuyingPrice, 36)).toFixed(4)}`);

    // 5. Calculate maxBuyingPrice, market price with an added premium
    const maxBuyingPrice = calculateMaxBuyingPrice(currentPricing, minBuyingPrice);
    log(`Calculated max buying price (market price + premium): ${Number(formatUnits(maxBuyingPrice, 36)).toFixed(4)}`);

    // 6. Set the prices on the ARM contract
    const targetBuyPrice = maxBuyingPrice;
    const targetSellPrice = parseUnits("1", 36); // Keep current sell price for now

    log(`New buy price: ${formatUnits(targetBuyPrice, 36)}`);
    log(`New sell price: ${formatUnits(targetSellPrice, 36)}`);

    if (block !== undefined) {
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
const estimateAverageWithdrawTime = async (arm, block) => {
    const blockTag = await getBlock(block);
    const timestamp = await hre.ethers.provider.getBlock(blockTag).then(b => b.timestamp);
    log(`Using block number: ${blockTag} at timestamp: ${timestamp}`);

    // Check if arm contract exist at this block
    const code = await hre.ethers.provider.getCode(arm.target, blockTag);
    if (code === "0x") {
        throw new Error(`ARM contract does not exist at block ${blockTag}`);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    /// --- Fetching wS holding from OS Vault
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    log(`\nFetching WS data from OS Vault ...`);
    let wSAvailable = 0n;
    const wSAddress = await arm.token0();
    const wS = await hre.ethers.getContractAt(
        [`function balanceOf(address owner) external view returns (uint256)`],
        wSAddress
    );
    wSAvailable += await wS.balanceOf(await arm.vault(), { blockTag });
    log(`ws balanceOf OSVault    : ${formatUnits(wSAvailable, 18)}`);

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    /// --- Fetching data from OS Vault
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    const vaultAddress = await arm.vault();
    const vault = await hre.ethers.getContractAt(
        [
            `function withdrawalQueueMetadata() external view returns (uint128,uint128,uint128,uint128)`,
            `function withdrawalRequests(uint256) external view returns (address,bool,uint40,uint128,uint128)`
        ],
        vaultAddress
    );
    const vaultQueuedWithdrawals = await vault.withdrawalQueueMetadata({ blockTag });
    wSAvailable += vaultQueuedWithdrawals[2] - vaultQueuedWithdrawals[0]; // += claimed amount - queued amount
    log(`Vault Queued amount     : ${formatUnits(vaultQueuedWithdrawals[0], 18)}`);
    log(`Vault Claimed amount    : ${formatUnits(vaultQueuedWithdrawals[2], 18)}`);
    log(`Vault Outstanding amount: ${formatUnits(vaultQueuedWithdrawals[0] - vaultQueuedWithdrawals[2], 18)}`);
    log(`Available wS in Vault   : ${formatUnits(wSAvailable, 18)}`);

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    /// --- Fetching oS holding from ARM
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    log(`\nFetching OS data from ARM ...`);
    const oSAddress = await arm.token1();
    const oS = await hre.ethers.getContractAt(
        [`function balanceOf(address owner) external view returns (uint256)`],
        oSAddress
    );

    let oSBalanceInARM = await oS.balanceOf(arm.target, { blockTag });
    log(`os balanceOf ARM        : ${formatUnits(oSBalanceInARM, 18)}`);

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    /// --- Fetching data from ARM
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    // This can be replaced with `getReserves()` once the function is added to the ARM contract
    const armWithdrawsQueued = await arm.withdrawsQueued({ blockTag });
    const armWithdrawsClaimed = await arm.withdrawsClaimed({ blockTag });
    const armOutstandingWithdrawals = armWithdrawsQueued - armWithdrawsClaimed;
    const oSAvailable = armOutstandingWithdrawals > oSBalanceInARM ? 0n : oSBalanceInARM - armOutstandingWithdrawals;
    log(`ARM Withdraws queued    : ${formatUnits(armWithdrawsQueued, 18)}`);
    log(`ARM Withdraws claimed   : ${formatUnits(armWithdrawsClaimed, 18)}`);
    log(`ARM Outstanding Withdraw: ${formatUnits(armOutstandingWithdrawals, 18)}`);
    log(`Available OS in ARM     : ${formatUnits(oSAvailable, 18)}\n`);

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    /// --- 1. There is more wS in Vault available than OS in ARM, no need to undelegate validator.
    /// --- Withdrawal time estimated to be close from: 1 day
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    if (wSAvailable >= oSAvailable) {
        log(`More wS available in Vault than OS in ARM, withdrawal time estimated to be close from: 1 day\n`);
        return 86400n;
    }

    // If wSAvailable < oSAvailable, we need to fetch from undelegating requests
    let amount = oSAvailable - wSAvailable;
    log(`Amount to fetch from undelegating requests : ${formatUnits(amount, 18)}\n`);

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    /// --- Fetching latests withdrawRequests from OS Vault
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    // Get total withdrawal count
    const totalWithdrawalsCount = await vault.withdrawalQueueMetadata({ blockTag });
    log(`Total request withdrawals                  : ${totalWithdrawalsCount[3]}`);
    const numberOfRecentRequests = 50;
    const recentWithdrawalRequests = await Promise.all(
        Array.from({ length: Math.min(numberOfRecentRequests, Number(totalWithdrawalsCount[3])) }, (_, i) =>
            vault.withdrawalRequests(Number(totalWithdrawalsCount[3]) - 1 - i, { blockTag })
        )
    );

    // Filter request that have been already claimed
    const unclaimedRequests = recentWithdrawalRequests.filter(req => !req[1]);
    log(`Unclaimed request count                    : ${unclaimedRequests.length.toString()}`);

    // Filter request that are older than 13 days
    const oldRequests = unclaimedRequests.filter(req => (BigInt(timestamp) - req[2]) >= 13 * 86400);
    log(`Unclaimed request > 13 days old            : ${oldRequests.length.toString()}`);
    // Sum the amount of all request that are 13 days older or more
    let sumOfOldRequestAmount = 0n;
    for (const req of oldRequests) {
        sumOfOldRequestAmount += req[3];
    }
    log(`Total amount from request > 13 days old    : ${formatUnits(sumOfOldRequestAmount, 18)}`);

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    /// --- 2. Sufficient withdrawal requests are nearing maturity to cover the required amount
    /// --- Withdrawal time estimated to be close from: 1 day
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    if (sumOfOldRequestAmount > amount) return 86400n;

    // Reduce amount by the sum of old requests
    amount -= sumOfOldRequestAmount;
    log(`Amount remaining minus > 13 days old reques: ${formatUnits(amount, 18)}`);

    // Filter request that are younger than 13 days (and not claimed)
    const recentRequests = unclaimedRequests.filter(req => (BigInt(timestamp) - req[2]) < 13 * 86400);
    log(`Unclaimed request < 13 days old            : ${recentRequests.length.toString()}`);
    let totalWeightedTime = 0n;
    let totalAmount = 0n;
    // Calculate the total weighted time and amount for recent requests
    // Iterate through requests starting from the most recent, prioritizing those closest to maturity
    log(`\nRequest < 13 days old data:`);
    for (let i = recentRequests.length - 1; i >= 0; i--) {
        const req = recentRequests[i];
        const weight = (14n * 86400n - (BigInt(timestamp) - req[2]));
        log(`- timestamp: ${req[2]} | amount: ${formatUnits(req[3], 18)}`);
        totalWeightedTime += weight * req[3];
        totalAmount += req[3];
        amount -= req[3];
        if (amount <= 0) break;
    }
    log(`\nTotal Amount from requests < 13 days old   : ${formatUnits(totalAmount, 18)}\n`);

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    /// --- 3. There is not enough requests to cover the amount needed.
    /// --- Withdrawal time estimated to be close from: 14 days (maximal)
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    if (amount > 0) {
        log(`\nNot enough recent requests to cover the total amount.\nEstimated withdrawal time: 14 days (maximum)\n`);
        return 14n * 86400n; // We didn't find enough recent requests to cover the amount
    }

    // If we reach this point, it means we found enough recent requests to use average weighted time
    totalWeightedTime += sumOfOldRequestAmount * 86400n;
    totalAmount += sumOfOldRequestAmount;

    log(`Total Amount (include all requests)        : ${formatUnits(totalAmount, 18)}\n`);

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    /// --- 4. There is enough requests to cover the amount needed.
    /// --- Withdrawal time calculated using average weighted time: between 1 day and 14 days
    ////////////////////////////////////////////////////////////////////////////////////////////////////
    log(`There is enough requests to cover the amount needed.`);
    log(
        `Estimated withdrawal time in days and hours:`,
        ((totalWeightedTime / totalAmount) / 86400n).toString(),
        `days`,
        ((totalWeightedTime / totalAmount) % 86400n / 3600n).toString(),
        `hours\n`
    );
    return totalWeightedTime / totalAmount;
}

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
