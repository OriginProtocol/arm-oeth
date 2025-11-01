const axios = require("axios");
const { parseUnits } = require("ethers");

const addresses = require("../utils/addresses");
const { sleep } = require("../utils/time");

const log = require("./logger")("utils:1inch");

const ONEINCH_API_ENDPOINT = "https://api.1inch.dev/swap/v6.1";

/**
 * Gets a swap quote from 1Inch's swap API
 * @param fromAsset The address of the asset to swap from.
 * @param toAsset The address of the asset to swap to.
 * @param fromAmount The unit amount of fromAsset to swap. eg 1.1 WETH = 1.1e18
 * See https://docs.1inch.io/docs/aggregation-protocol/api/swagger
 */
const get1InchSwapQuote = async ({
  fromAsset,
  toAsset,
  fromAmount,
  excludedProtocols,
  chainId = 1,
}) => {
  const apiKey = process.env.ONEINCH_API_KEY;
  if (!apiKey) {
    throw Error(
      "ONEINCH_API_KEY environment variable not set. Visit the 1Inch Dev Portal https://portal.1inch.dev/",
    );
  }

  const params = {
    src: fromAsset,
    dst: toAsset,
    amount: fromAmount.toString(),
    includeProtocols: true,
    includeGas: false,
    includeTokensInfo: false,
    excludedProtocols: excludedProtocols || [],
  };
  log("swap API params: ", params);

  let retries = 3;

  while (retries > 0) {
    const quoteUrl = `${ONEINCH_API_ENDPOINT}/${chainId}/quote`;
    try {
      const response = await axios.get(quoteUrl, {
        params,
        headers: {
          Authorization: `Bearer ${apiKey}`,
        },
      });

      if (!response.data.dstAmount) {
        console.error(response.data);
        throw Error("response is missing dstAmount");
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
          `Failed to get a 1Inch quote. Will try again in 2 seconds with ${retries} retries left`,
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

/**
 * Gets 1Inch prices for buying and selling the base asset using the liquid asset.
 * @param {*} amount Amount not scaled to 18 decimals
 * @param {*} assets liquidity and base asset addresses. eg WETH and stETH
 * @param {BigInt} fee 1Inch infrastructure fee in basis points.
 * 10 = 0.1% for stable coins. eg stETH
 * 30 = 0.3% for non-stable coins. eg OS
 * https://portal.1inch.dev/documentation/faq/infrastructure-fee
 */
const get1InchPrices = async (
  amount,
  assets = {
    liquid: addresses.mainnet.WETH,
    base: addresses.mainnet.stETH,
  },
  fee = 10n,
  chainId = 1,
) => {
  const amountBI = parseUnits(amount.toString(), 18);

  const buyQuote = await get1InchSwapQuote({
    fromAsset: assets.liquid,
    toAsset: assets.base,
    fromAmount: amountBI, // liquid amount
    excludedProtocols: "ORIGIN",
    chainId,
  });
  // base buy amount adjusted by 1Inch's infrastructure fee
  const buyToAmount = (BigInt(buyQuote.dstAmount) * (10000n + fee)) / 10000n;
  // stETH/ETH rate = ETH amount / stETH amount
  const buyPrice = (amountBI * BigInt(1e18)) / buyToAmount;

  await sleep(800);

  const sellQuote = await get1InchSwapQuote({
    fromAsset: assets.base,
    toAsset: assets.liquid,
    fromAmount: amountBI, // base amount
    excludedProtocols: "ORIGIN",
    chainId,
  });
  // liquid sell amount adjusted by 1Inch's infrastructure fee
  const sellToAmount = (BigInt(sellQuote.dstAmount) * (10000n + fee)) / 10000n;
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
