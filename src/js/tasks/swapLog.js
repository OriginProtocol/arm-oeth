const { formatUnits } = require("ethers");

const { logLiquidity } = require("./liquidity");
const { get1InchPrices } = require("../utils/1Inch");
const { logBlock } = require("../utils/block");

const log = require("../utils/logger")("task:swapLog");

const snap = async (options) => {
  await logBlock();

  if (options.oneInch) {
    await log1InchPrices(options);
  }

  if (options.liq) {
    await logLiquidity(options);
  }
};

const poller = async (options) => {
  const { interval } = options;

  console.log(`timestamp,amount,sell,mid,buy,spread,sellGas,buyGas`);

  // Do an initial poll immediately
  await poll1InchPrices(options);

  // Poll every interval minutes
  setInterval(async () => {
    await poll1InchPrices(options);
  }, interval * 60 * 1000);

  // Keep the process running by waiting on a promise that never resolves
  await new Promise(() => {});
};

const poll1InchPrices = async (options) => {
  const oneInch = await get1InchPrices(options);
  console.log(
    `${Math.trunc(Date.now() / 1000)},${options.amount},${formatUnits(
      oneInch.sellPrice,
      18
    )},${formatUnits(oneInch.midPrice, 18)},${formatUnits(
      oneInch.buyPrice,
      18
    )},${formatUnits(oneInch.spread, 18)},${oneInch.sellGas},${oneInch.buyGas}`
  );
};

const log1InchPrices = async (options) => {
  const { amount, pair, paths } = options;

  const oneInch = await get1InchPrices(options);

  log(`buy  ${formatUnits(oneInch.buyToAmount)} stETH for ${amount} WETH`);
  log(`sell ${amount} stETH for ${formatUnits(oneInch.sellToAmount)} WETH`);

  console.log(`\n1Inch prices for swap size ${amount}`);
  console.log(
    `buy     : ${formatUnits(
      oneInch.buyPrice,
      18
    )} ${pair}, ${oneInch.buyGas.toLocaleString()} gas`
  );

  console.log(`mid     : ${formatUnits(oneInch.midPrice, 18)} ${pair}`);

  console.log(
    `sell    : ${formatUnits(
      oneInch.sellPrice,
      18
    )} ${pair}, ${oneInch.sellGas.toLocaleString()} gas`
  );
  console.log(`spread  : ${formatUnits(oneInch.spread, 14)} bps`);

  if (paths) {
    console.log(`buy path for ${pair}`);
    log1InchProtocols(oneInch.buyQuote);

    console.log(`sell path for ${pair}`);
    log1InchProtocols(oneInch.sellQuote);
  }

  return oneInch;
};

const log1InchProtocols = (sellQuote) => {
  // console.log("%j", sellQuote.protocols);

  // TODO need to better handle
  sellQuote.protocols.forEach((p1) => {
    p1.forEach((p2) => {
      p2.forEach((p3) => {
        console.log(
          `${p3.part.toString().padEnd(3)}% ${p3.name.padEnd(12)} ${
            p3.fromTokenAddress
          } -> ${p3.toTokenAddress}`
        );
      });
    });
  });
};

module.exports = { poller, snap };
