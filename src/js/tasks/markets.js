const { formatUnits } = require("ethers");

const { get1InchPrices } = require("../utils/1Inch");
const { getCurvePrices } = require("../utils/curve");
const { getUniswapV3SpotPrices } = require("../utils/uniswap");

const log = require("../utils/logger")("task:markets");

const logArmPrices = async (arm, blockTag) => {
  console.log(`\nARM Prices`);
  // The rate of 1 WETH for stETH to 36 decimals from the perspective of the AMM. ie WETH/stETH
  // from the trader's perspective, this is the stETH/WETH buy price
  const OWethStEthRate = await arm.traderate0({ blockTag });
  console.log(`traderate0: ${formatUnits(OWethStEthRate, 36)} WETH/stETH`);

  // convert from WETH/stETH rate with 36 decimals to stETH/WETH rate with 18 decimals
  const sellPrice = BigInt(1e54) / BigInt(OWethStEthRate);

  // The rate of 1 stETH for WETH to 36 decimals. ie stETH/WETH
  const OStEthWethRate = await arm.traderate1({ blockTag });
  console.log(`traderate1: ${formatUnits(OStEthWethRate, 36)} stETH/WETH`);
  // Convert back to 18 decimals
  const buyPrice = BigInt(OStEthWethRate) / BigInt(1e18);

  const midPrice = (sellPrice + buyPrice) / 2n;

  const crossPrice = await arm.crossPrice({ blockTag });

  console.log(`sell   : ${formatUnits(sellPrice, 18).padEnd(20)} stETH/WETH`);
  if (crossPrice > sellPrice) {
    console.log(
      `cross  : ${formatUnits(crossPrice, 36).padEnd(20)} stETH/WETH`
    );
    console.log(`mid    : ${formatUnits(midPrice, 18).padEnd(20)} stETH/WETH`);
  } else {
    console.log(`mid    : ${formatUnits(midPrice, 18).padEnd(20)} stETH/WETH`);
    console.log(
      `cross  : ${formatUnits(crossPrice, 18).padEnd(20)} stETH/WETH`
    );
  }
  console.log(`buy    : ${formatUnits(buyPrice, 18).padEnd(20)} stETH/WETH`);

  const spread = BigInt(sellPrice) - BigInt(buyPrice);
  // Origin rates are to 36 decimals
  console.log(`spread : ${formatUnits(spread, 14)} bps`);

  return {
    buyPrice: sellPrice,
    sellPrice: buyPrice,
    midPrice,
    crossPrice,
    spread,
  };
};

const log1InchPrices = async (amount, ammPrices) => {
  const oneInch = await get1InchPrices(amount);

  log(`buy  ${formatUnits(oneInch.buyToAmount)} stETH for ${amount} WETH`);
  log(`sell ${amount} stETH for ${formatUnits(oneInch.sellToAmount)} WETH`);

  console.log(`\n1Inch prices for swap size ${amount}`);
  const buyRateDiff = oneInch.buyPrice - ammPrices.buyPrice;
  console.log(
    `buy    : ${formatUnits(oneInch.buyPrice, 18).padEnd(
      20
    )} stETH/WETH, diff ${formatUnits(buyRateDiff, 14).padEnd(
      17
    )} bps to ARM, ${oneInch.buyGas.toLocaleString()} gas`
  );

  const midRateDiff = oneInch.midPrice - ammPrices.midPrice;
  console.log(
    `mid    : ${formatUnits(oneInch.midPrice, 18).padEnd(
      20
    )} stETH/WETH, diff ${formatUnits(midRateDiff, 14).padEnd(17)} bps to ARM`
  );

  const sellRateDiff = oneInch.sellPrice - ammPrices.sellPrice;
  console.log(
    `sell   : ${formatUnits(oneInch.sellPrice, 18).padEnd(
      20
    )} stETH/WETH, diff ${formatUnits(sellRateDiff, 14).padEnd(
      17
    )} bps to ARM, ${oneInch.sellGas.toLocaleString()} gas`
  );
  console.log(`spread : ${formatUnits(oneInch.spread, 14)} bps`);

  console.log(`buy path for stETH/WETH`);
  log1InchProtocols(oneInch.buyQuote);

  console.log(`sell path for stETH/WETH`);
  log1InchProtocols(oneInch.sellQuote);

  return oneInch;
};

const log1InchProtocols = (sellQuote) => {
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

const logCurvePrices = async (options, ammPrices) => {
  const { amount, pair, poolName } = options;

  const curve = await getCurvePrices(options);
  const buyRateDiff = curve.buyPrice - ammPrices.buyPrice;
  const midRateDiff = curve.midPrice - ammPrices.midPrice;
  const sellRateDiff = curve.sellPrice - ammPrices.sellPrice;

  log(`buy  ${formatUnits(curve.buyToAmount)} stETH for ${amount} WETH`);
  log(`sell ${amount} stETH for ${formatUnits(curve.sellToAmount)} WETH`);

  console.log(`\n${poolName} Curve prices for swap size ${amount}`);
  console.log(
    `buy    : ${formatUnits(curve.buyPrice, 18).padEnd(
      20
    )} ${pair}, diff ${formatUnits(buyRateDiff, 14).padEnd(
      17
    )} bps to ARM, ${curve.buyGas.toLocaleString()} gas`
  );
  console.log(
    `mid    : ${formatUnits(curve.midPrice, 18).padEnd(
      20
    )} ${pair}, diff ${formatUnits(midRateDiff, 14).padEnd(17)} bps to ARM`
  );
  console.log(
    `sell   : ${formatUnits(curve.sellPrice, 18).padEnd(
      20
    )} ${pair}, diff ${formatUnits(sellRateDiff, 1).padEnd(
      17
    )} bps to ARM, ${curve.sellGas.toLocaleString()} gas`
  );
  console.log(`spread : ${formatUnits(curve.spread, 14)} bps`);

  return curve;
};

const logUniswapSpotPrices = async (options, ammPrices) => {
  const { amount, pair } = options;
  const uniswap = await getUniswapV3SpotPrices(options);
  const buyRateDiff = uniswap.buyPrice - ammPrices.buyPrice;
  const midRateDiff = uniswap.midPrice - ammPrices.midPrice;
  const sellRateDiff = uniswap.sellPrice - ammPrices.sellPrice;

  log(`buy  ${formatUnits(uniswap.buyToAmount)} stETH for ${amount} WETH`);
  log(`sell ${amount} stETH for ${formatUnits(uniswap.sellToAmount)} WETH`);

  console.log(
    `\nwstETH/ETH 0.01% Uniswap V3 spot prices for swap size ${amount}`
  );
  console.log(
    `buy     : ${formatUnits(uniswap.buyPrice, 18).padEnd(
      20
    )} ${pair}, diff ${formatUnits(
      buyRateDiff,
      14
    )} bps to ARM, ${uniswap.buyGas.toLocaleString()} gas`
  );
  console.log(
    `mid     : ${formatUnits(uniswap.midPrice, 18).padEnd(
      20
    )} ${pair}, diff ${formatUnits(midRateDiff, 14)} bps to ARM`
  );
  console.log(
    `sell    : ${formatUnits(uniswap.sellPrice, 18).padEnd(
      20
    )} ${pair}, diff ${formatUnits(
      sellRateDiff,
      14
    )} bps to ARM, ${uniswap.sellGas.toLocaleString()} gas`
  );
  console.log(`spread  : ${formatUnits(uniswap.spread, 14)} bps`);

  return uniswap;
};

module.exports = {
  log1InchPrices,
  logArmPrices,
  logCurvePrices,
  logUniswapSpotPrices,
};
