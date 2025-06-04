const axios = require("axios");
const { formatUnits, parseUnits, Interface } = require("ethers");

const { resolveAddress } = require("../utils/assets");
const MagpieBaseURL = "https://api.magpiefi.xyz/aggregator";

const log = require("../utils/logger")("utils:magpie");

const magpieQuote = async ({
  from,
  to,
  amount,
  slippage,
  swapper,
  recipient,
}) => {
  const fromAsset = await resolveAddress(from);
  const toAsset = await resolveAddress(to);

  const params = {
    network: "sonic",
    fromTokenAddress: fromAsset,
    toTokenAddress: toAsset,
    sellAmount: amount.toString(),
    slippage,
    gasless: false,
    fromAddress: swapper,
    toAddress: recipient,
  };

  log(`Magpie quote params: `, params);

  try {
    const response = await axios.get(`${MagpieBaseURL}/quote`, {
      params,
    });

    const toAmount = parseUnits(response.data.amountOut, 18);
    const price = (amount * parseUnits("1", 22)) / toAmount;

    // log("Magpie quote response: ", response.data);

    const id = response.data.id;
    const minAmountOut = response.data.amountOutMin;
    log(`Quote id : ${id}`);
    log(`${from}/${to} sell price: ${formatUnits(price, 4)}`);

    const data = await magpieTx({ id });

    return { price, fromAsset, toAsset, minAmountOut, data };
  } catch (err) {
    if (err.response) {
      console.error("Response data  : ", err.response.data);
      console.error("Response status: ", err.response.status);
    }
    throw Error(`Call to Magpie quote API failed: ${err.message}`);
  }
};

const magpieTx = async ({ id }) => {
  const params = {
    quoteId: id,
    estimateGas: false,
  };

  log(`Magpie transaction params: `, params);

  try {
    const response = await axios.get(`${MagpieBaseURL}/transaction`, {
      params,
    });

    // log("Magpie transaction response: ", response.data);
    // log(`Transaction data: ${response.data.data}`);

    const iface = new Interface([
      "function swapWithMagpieSignature(bytes) view returns (uint256)",
    ]);

    const decodedData = iface.decodeFunctionData(
      "swapWithMagpieSignature",
      response.data.data
    );
    log(`Decoded swap data: ${decodedData}`);

    return decodedData[0];
  } catch (err) {
    if (err.response) {
      console.error("Response data  : ", err.response.data);
      console.error("Response status: ", err.response.status);
    }
    throw Error(`Call to Magpie quote API failed: ${err.message}`);
  }
};

module.exports = { magpieQuote, magpieTx };
