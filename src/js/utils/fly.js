const axios = require("axios");
const fetch = require("node-fetch");
const { formatUnits, parseUnits, Interface } = require("ethers");

/// --- Note: ---
/// This file is named magpie.js, but it contains functions for interacting with FlyTrade, new name from the original Magpie.
/// ---

const { resolveAddress } = require("./assets");
const FlyTradeBaseURL = "https://api.fly.trade/aggregator";

const log = require("./logger")("utils:fly");

// This list comes from https://api.fly.trade/aggregator/liquidity-sources?networkName=sonic
// With the Origin ARM removed
const liquiditySources = [
  "sonic-market-v2",
  "sonic-market-v2-lp",
  "beethoven-x-stable",
  "beethoven-x-weighted",
  "metropolis-2v1",
  "metropolis",
  "spooky-swap-v2",
  "spooky-swap-v2-lp",
  "spooky-swap-v3",
  "wagmi",
  "oku",
  "equalizer-v2-stable",
  "equalizer-v2-volatile",
  "equalizer-v3",
  "solidly-v3",
  "silver-swap",
  "beets-lst",
  "rings-usdc",
  "rings-eth",
  "woo-fi",
  "sushi",
  "sushi-lp",
  "sushi-v3",
  "clober-v2",
  "shadow",
  "mobius",
  "swapx-stable",
  "swapx-volatile",
  "swapx-cl",
  "rings-stk-sc-usdc",
  "rings-stk-sc-eth",
  "shadow-stable",
  "shadow-volatile",
  "curve-crypto",
  "curve-stable",
  "curve-crypto-lp",
  "curve-stable-lp",
  "dyor-swap",
  "erc-4626",
  "beets",
  "amped",
  "beets-v3-stable",
  "beets-v3-weighted",
  "defive",
  "defive-lp",
  "xpress",
  "equalizer-v2-lp",
  "aave-v3",
  "angles",
  "lucidly",
  "bmx",
  "atlantis",
  "zk-swap-v3",
  "thick",
  "stout",
  "peapods-v3",
  "origin-os",
  // "origin-arm",
  "beets-v3-reclamm",
  "swapx-lp",
  "shadow-lp",
  "zk-swap",
  "fatfinger",
  "fatfinger-lp",
];

const flyTradeQuote = async ({
  from,
  to,
  amount,
  slippage,
  swapper,
  recipient,
  getData = true,
}) => {
  const fromAsset = await resolveAddress(from);
  const toAsset = await resolveAddress(to);
  const urlQuery = [
    `network=sonic`,
    `fromTokenAddress=${fromAsset}`,
    `toTokenAddress=${toAsset}`,
    `sellAmount=${amount}`,
    `fromAddress=${swapper}`,
    `toAddress=${recipient}`,
    `slippage=${slippage}`,
    `liquiditySources=${liquiditySources}`,
    `gasless=false`,
  ].join("&");

  try {
    const response = await fetch(`${FlyTradeBaseURL}/quote?${urlQuery}`, {
      method: "GET",
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36",
      },
    });

    if (!response.ok || response.status !== 200) {
      console.log("Fly.trade response:");
      console.log(response);
      console.log(await response.text());
      throw new Error(
        `Failed to get price quote from fly.trade: ${response.statusText}`,
      );
    }

    const responseData = await response.json();

    // log("FlyTrade quote response: ", responseData);
    const toAmount = parseUnits(responseData.amountOut, 18);
    const price = (amount * parseUnits("1", 36)) / toAmount;

    const fees = responseData.typedData.message.swapFee;
    const id = responseData.id;
    const minAmountOut = responseData.typedData.messageamountOutMin;
    log(`Quote id : ${id}`);
    log(`${from}/${to} sell price: ${formatUnits(price, 4)}`);

    const data = getData ? await flyTradeTx({ id }) : undefined;

    return { price, fromAsset, toAsset, minAmountOut, data, fees };
  } catch (err) {
    if (err.response) {
      console.error("Response data  : ", err.response.data);
      console.error("Response status: ", err.response.status);
    }
    throw Error(`Call to FlyTrade quote API failed: ${err.message}`);
  }
};

const flyTradeTx = async ({ id }) => {
  const params = {
    quoteId: id,
    estimateGas: false,
  };

  log(`FlyTrade transaction params: `, params);

  try {
    const response = await axios.get(`${FlyTradeBaseURL}/transaction`, {
      params,
    });

    // -------------------------------  ⚠️ ⚠️ ⚠️ ------------------------------- //
    // NEVER DELETE THE FOLLOWING `CONSOLE.LOG` IT IS USED IN THE TEST, BY FFI !!!
    // -------------------------------  ⚠️ ⚠️ ⚠️ ------------------------------- //
    console.log(`0x${response.data.data.slice(10)}`);

    log("FlyTrade transaction response: ", response);

    const iface = new Interface([
      "function swapWithMagpieSignature(bytes) view returns (uint256)",
    ]);

    const decodedData = iface.decodeFunctionData(
      "swapWithMagpieSignature",
      response.data.data,
    );
    log(`Decoded swap data: ${decodedData}`);

    return decodedData[0];
  } catch (err) {
    if (err.response) {
      console.error("Response data  : ", err.response.data);
      console.error("Response status: ", err.response.status);
    }
    throw Error(`Call to FlyTrade quote API failed: ${err.message}`);
  }
};

module.exports = { flyTradeQuote, flyTradeTx };
