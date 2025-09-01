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
    const duration = await calculateAveragePeriod(arm);
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
