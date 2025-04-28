const axios = require("axios");
const { formatUnits, parseUnits } = require("ethers");

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

  const fromAmount = parseUnits(amount.toString(), 18);

  const params = {
    network: "sonic",
    fromTokenAddress: fromAsset,
    toTokenAddress: toAsset,
    sellAmount: fromAmount.toString(),
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
    const sellPrice = (fromAmount * parseUnits("1", 22)) / toAmount;

    // log("Magpie quote response: ", response.data);

    console.log(`Quote id : ${response.data.id}`);
    console.log(`${from}/${to} sell price: ${formatUnits(sellPrice, 4)}`);

    return sellPrice;
  } catch (err) {
    if (err.response) {
      console.error("Response data  : ", err.response.data);
      console.error("Response status: ", err.response.status);
    }
    throw Error(`Call to Magpie quote API failed: ${err.message}`);
  }
};

module.exports = { magpieQuote };
