const axios = require("axios");
const { parseUnits } = require("ethers");

const addresses = require("../utils/addresses");
const { sleep } = require("../utils/time");

const log = require("./logger")("utils:1inch");

const ONEINCH_API_ENDPOINT = "https://api.1inch.dev/swap/v5.2/1/quote";

/**
 * Gets a swap quote from 1Inch's V5.2 swap API
 * @param fromAsset The address of the asset to swap from.
 * @param toAsset The address of the asset to swap to.
 * @param fromAmount The unit amount of fromAsset to swap. eg 1.1 WETH = 1.1e18
 * See https://docs.1inch.io/docs/aggregation-protocol/api/swagger
 */
const get1InchSwapQuote = async ({ fromAsset, toAsset, fromAmount }) => {
  const apiKey = process.env.ONEINCH_API_KEY;
  if (!apiKey) {
    throw Error(
      "ONEINCH_API_KEY environment variable not set. Visit the 1Inch Dev Portal https://portal.1inch.dev/"
    );
  }

  const params = {
    src: fromAsset,
    dst: toAsset,
    amount: fromAmount.toString(),
    allowPartialFill: true,
    disableEstimate: true,
    includeProtocols: true,
    includeGas: true,
    includeTokensInfo: false,
  };
  log("swap API params: ", params);

  let retries = 3;

  while (retries > 0) {
    try {
      const response = await axios.get(ONEINCH_API_ENDPOINT, {
        params,
        headers: {
          Authorization: `Bearer ${apiKey}`,
        },
      });

      if (!response.data.toAmount) {
        console.error(response.data);
        throw Error("response is missing toAmount");
      }

      log("swap API response data: %j", response.data);

      return response.data;
    } catch (err) {
      if (err.response) {
        console.error("Response data  : ", err.response.data);
        console.error("Response status: ", err.response.status);
        console.error("Response status: ", err.response.statusText);
      }
      if (err.response?.status == 429) {
        retries = retries - 1;
        console.error(
          `Failed to get a 1Inch quote. Will try again in 2 seconds with ${retries} retries left`
        );
        // Wait for 2s before next try
        await new Promise((r) => setTimeout(r, 2000));
        continue;
      }
      throw Error(`Call to 1Inch swap quote API failed: ${err.message}`);
    }
  }

  throw Error(`Call to 1Inch swap quote API failed: Rate-limited`);
};

const get1InchPrices = async (amount) => {

  const amountBI = parseUnits(amount.toString(), 18);

  const buyQuote = await get1InchSwapQuote({
    fromAsset: addresses.mainnet.WETH,
    toAsset: addresses.mainnet.stETH,
    fromAmount: amountBI, // WETH amount
  });
  // stETH buy amount
  const buyToAmount = BigInt(buyQuote.toAmount);
  // stETH/ETH rate = ETH amount / stETH amount
  const buyPrice = (amountBI * BigInt(1e18)) / buyToAmount;

  await sleep(800);

  const sellQuote = await get1InchSwapQuote({
    fromAsset: addresses.mainnet.stETH,
    toAsset: addresses.mainnet.WETH,
    fromAmount: amountBI, // stETH amount
  });
  // WETH sell amount
  const sellToAmount = BigInt(sellQuote.toAmount);
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

module.exports = { get1InchSwapQuote, get1InchPrices };
