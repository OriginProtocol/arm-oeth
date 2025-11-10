const axios = require("axios");
const { parseUnits } = require("ethers");

const addresses = require("./addresses");
const { sleep } = require("./time");

const log = require("./logger")("utils:kyber");

const KYBER_API_ENDPOINT = "https://aggregator-api.kyberswap.com";

const originSources = "generic-arm";

/**
 * Gets a swap quote from Kyber's swap route API
 * @param tokenIn The address of the asset to swap from.
 * @param tokenOut The address of the asset to swap to.
 * @param amountIn The unit amount of tokenIn to swap. eg 1.1 WETH = 1.1e18
 * See https://docs.kyberswap.com/kyberswap-solutions/kyberswap-aggregator/aggregator-api-specification/evm-swaps#get-chain-api-v1-routes
 */
const getKyberSwapQuote = async ({
  tokenIn,
  tokenOut,
  amountIn,
  excludedSources,
}) => {
  const params = {
    tokenIn,
    tokenOut,
    amountIn: amountIn.toString(),
    gasInclude: false,
    excludedSources: excludedSources || [],
  };
  log("swap API params: ", params);

  let retries = 3;

  while (retries > 0) {
    const url = `${KYBER_API_ENDPOINT}/ethereum/api/v1/routes`;
    try {
      const response = await axios.get(url, {
        params,
        headers: {
          "X-Client-Id": "Origin-ARM",
        },
      });

      if (!response.data?.data?.routeSummary?.amountOut) {
        console.error(response.data);
        throw Error("response is missing data.data.routeSummary.amountOut");
      }

      log("swap API response data: %j", response.data);

      return response.data.data.routeSummary;
    } catch (err) {
      if (err.response) {
        console.error("Response data  : ", err.response.data);
        console.error("Response status: ", err.response.status);
        console.error("Response status: ", err.response.statusText);
      }
      if (err.response?.status == 429) {
        retries = retries - 1;
        console.error(
          `Failed to get a Kyber swap route. Will try again in 2 seconds with ${retries} retries left`,
        );
        // Wait for 2s before next try
        await new Promise((r) => setTimeout(r, 2000));
        continue;
      }
      throw Error(`Call to Kyber swap route API failed: ${err.message}`);
    }
  }

  throw Error(`Call to Kyber swap route API failed: Rate-limited`);
};

/**
 * Gets Kyber prices for buying and selling the base asset using the liquid asset.
 * @param {*} amount Amount not scaled to 18 decimals
 * @param {*} assets liquidity and base asset addresses. eg WETH and stETH
 */
const getKyberPrices = async (
  amount,
  assets = {
    liquid: addresses.mainnet.WETH,
    base: addresses.mainnet.stETH,
  },
) => {
  const amountBI = parseUnits(amount.toString(), 18);

  const buyQuote = await getKyberSwapQuote({
    tokenIn: assets.liquid,
    tokenOut: assets.base,
    amountIn: amountBI, // liquid amount
    excludedSources: originSources,
  });
  const buyToAmount = BigInt(buyQuote.amountOut);
  // stETH/ETH rate = ETH amount / stETH amount
  const buyPrice = (amountBI * BigInt(1e18)) / buyToAmount;

  await sleep(800);

  const sellQuote = await getKyberSwapQuote({
    tokenIn: assets.base,
    tokenOut: assets.liquid,
    amountIn: amountBI, // base amount
    excludedSources: originSources,
  });
  const sellToAmount = BigInt(sellQuote.amountOut);
  // stETH/WETH rate = WETH amount / stETH amount
  const sellPrice = (sellToAmount * BigInt(1e18)) / amountBI;

  const midPrice = (buyPrice + sellPrice) / 2n;
  const spread = buyPrice - sellPrice;

  return {
    buyQuote,
    buyToAmount,
    buyPrice,
    buyGas: buyQuote.gas,
    sellQuote,
    sellToAmount,
    sellPrice,
    sellGas: sellQuote.gas,
    midPrice,
    spread,
  };
};

module.exports = { getKyberSwapQuote, getKyberPrices };
