const { formatUnits, parseUnits } = require("ethers");

const addresses = require("../utils/addresses");
const { get1InchPrices } = require("../utils/1Inch");
const { getCurvePrices } = require("../utils/curve");
const { getUniswapV3SpotPrices } = require("../utils/uniswap");
const { getSigner } = require("../utils/signers");
const { getFluidSpotPrices } = require("../utils/fluid");

const log = require("../utils/logger")("task:markets");

const logArmPrices = async ({ blockTag, gas }, arm) => {
  console.log(`\nARM Prices`);
  // The rate of 1 WETH for stETH to 36 decimals from the perspective of the AMM. ie WETH/stETH
  // from the trader's perspective, this is the stETH/WETH buy price
  const OWethStEthRate = await arm.traderate0({ blockTag });

  // convert from WETH/stETH rate with 36 decimals to stETH/WETH rate with 18 decimals
  const sellPrice = BigInt(1e54) / BigInt(OWethStEthRate);

  // The rate of 1 stETH for WETH to 36 decimals. ie stETH/WETH
  const OStEthWethRate = await arm.traderate1({ blockTag });
  // Convert back to 18 decimals
  const buyPrice = BigInt(OStEthWethRate) / BigInt(1e18);

  const midPrice = (sellPrice + buyPrice) / 2n;

  const crossPrice = await arm.crossPrice({ blockTag });

  let buyGasCosts = "";
  let sellGasCosts = "";
  if (gas) {
    const signer = await getSigner();
    const amountBI = parseUnits("0.01", 18);
    try {
      const buyGas = await arm
        .connect(signer)
        [
          "swapExactTokensForTokens(address,address,uint256,uint256,address)"
        ].estimateGas(addresses.mainnet.WETH, addresses.mainnet.stETH, amountBI, 0, addresses.dead, {
          blockTag,
        });
      buyGasCosts = `, ${buyGas.toLocaleString()} gas`;
    } catch (e) {
      log(`Failed to estimate buy gas for swap: ${e.message}`);
    }
    try {
      const sellGas = await arm
        .connect(signer)
        [
          "swapExactTokensForTokens(address,address,uint256,uint256,address)"
        ].estimateGas(addresses.mainnet.stETH, addresses.mainnet.WETH, amountBI, 0, addresses.dead, {
          blockTag,
        });
      sellGasCosts = `, ${sellGas.toLocaleString()} gas`;
    } catch (e) {
      log(`Failed to estimate sell gas for swap: ${e.message}`);
    }
  }

  console.log(
    `sell   : ${formatUnits(sellPrice, 18).padEnd(
      20,
    )} stETH/WETH${sellGasCosts}`,
  );
  if (crossPrice > sellPrice) {
    console.log(
      `cross  : ${formatUnits(crossPrice, 36).padEnd(20)} stETH/WETH`,
    );
    console.log(`mid    : ${formatUnits(midPrice, 18).padEnd(20)} stETH/WETH`);
  } else {
    console.log(`mid    : ${formatUnits(midPrice, 18).padEnd(20)} stETH/WETH`);
    console.log(
      `cross  : ${formatUnits(crossPrice, 18).padEnd(20)} stETH/WETH`,
    );
  }
  console.log(
    `buy    : ${formatUnits(buyPrice, 18).padEnd(20)} stETH/WETH${buyGasCosts}`,
  );

  const spread = BigInt(sellPrice) - BigInt(buyPrice);
  // Origin rates are to 36 decimals
  console.log(`spread : ${formatUnits(spread, 14)} bps`);

  // take 80% of the discount to cover the 20% fee
  const buyDiscount = BigInt(1e18) - buyPrice;
  const buyDiscountPostFee = (buyDiscount * 8n) / 10n;

  console.log(
    `\nYield on ${formatUnits(
      buyDiscount * 10000n,
      18,
    )} bps buy discount after fee`,
  );
  console.log(
    `1 day ${formatUnits(
      buyDiscountPostFee * 36500n,
      18,
    )}%, 2 days ${formatUnits(
      (buyDiscountPostFee * 36500n) / 2n,
      18,
    )}%, 3 days ${formatUnits(
      (buyDiscountPostFee * 36500n) / 3n,
      18,
    )}%, 4 days ${formatUnits(
      (buyDiscountPostFee * 36500n) / 4n,
      18,
    )}%, 5 days ${formatUnits((buyDiscountPostFee * 36500n) / 5n, 18)}% APY`,
  );

  return {
    buyPrice,
    sellPrice,
    midPrice,
    spread,
  };
};

const log1InchPrices = async ({ amount, gas }, ammPrices) => {
  const oneInch = await get1InchPrices(amount);

  log(`buy  ${formatUnits(oneInch.buyToAmount)} stETH for ${amount} WETH`);
  log(`sell ${amount} stETH for ${formatUnits(oneInch.sellToAmount)} WETH`);

  console.log(`\n1Inch buy path for stETH/WETH`);
  log1InchProtocols(oneInch.buyQuote);

  console.log(`\n1Inch sell path for stETH/WETH`);
  log1InchProtocols(oneInch.sellQuote);

  console.log(`\n1Inch prices for swap size ${amount}`);
  const buyRateDiff = oneInch.buyPrice - ammPrices.sellPrice;
  const buyGasCosts = gas ? `, ${oneInch.buyGas.toLocaleString()} gas` : "";
  console.log(
    `buy    : ${formatUnits(oneInch.buyPrice, 18).padEnd(
      20,
    )} stETH/WETH, diff ${formatUnits(buyRateDiff, 14).padEnd(
      17,
    )} bps to ARM${buyGasCosts}`,
  );

  console.log(
    `mid    : ${formatUnits(oneInch.midPrice, 18).padEnd(20)} stETH/WETH`,
  );

  const sellRateDiff = oneInch.sellPrice - ammPrices.buyPrice;
  const sellGasCosts = gas ? `, ${oneInch.sellGas.toLocaleString()} gas` : "";
  console.log(
    `sell   : ${formatUnits(oneInch.sellPrice, 18).padEnd(
      20,
    )} stETH/WETH, diff ${formatUnits(sellRateDiff, 14).padEnd(
      17,
    )} bps to ARM${sellGasCosts}`,
  );
  console.log(`spread : ${formatUnits(oneInch.spread, 14)} bps`);

  console.log(
    `\nBest buy : ${
      ammPrices.sellPrice < oneInch.buyPrice ? "Origin" : "1Inch"
    }`,
  );
  console.log(
    `Best sell: ${ammPrices.buyPrice > oneInch.sellPrice ? "Origin" : "1Inch"}`,
  );

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
          } -> ${p3.toTokenAddress}`,
        );
      });
    });
  });
};

const logCurvePrices = async (options, ammPrices) => {
  const { amount, pair, poolName, gas } = options;

  const curve = await getCurvePrices(options);
  const buyRateDiff = curve.buyPrice - ammPrices.sellPrice;
  const sellRateDiff = curve.sellPrice - ammPrices.buyPrice;

  log(`buy  ${formatUnits(curve.buyToAmount)} stETH for ${amount} WETH`);
  log(`sell ${amount} stETH for ${formatUnits(curve.sellToAmount)} WETH`);

  console.log(`\n${poolName} Curve prices for swap size ${amount}`);
  const buyGasCosts = gas ? `, ${curve.buyGas.toLocaleString()} gas` : "";
  const sellGasCosts = gas ? `, ${curve.sellGas.toLocaleString()} gas` : "";
  console.log(
    `buy    : ${formatUnits(curve.buyPrice, 18).padEnd(
      20,
    )} ${pair}, diff ${formatUnits(buyRateDiff, 14).padEnd(
      17,
    )} bps to ARM${buyGasCosts}`,
  );
  console.log(`mid    : ${formatUnits(curve.midPrice, 18).padEnd(20)} ${pair}`);
  console.log(
    `sell   : ${formatUnits(curve.sellPrice, 18).padEnd(
      20,
    )} ${pair}, diff ${formatUnits(sellRateDiff, 14).padEnd(
      17,
    )} bps to ARM${sellGasCosts}`,
  );
  console.log(`spread : ${formatUnits(curve.spread, 14)} bps`);

  return curve;
};

const logUniswapSpotPrices = async (options, ammPrices) => {
  const { amount, pair, gas } = options;
  const uniswap = await getUniswapV3SpotPrices(options);
  const buyRateDiff = uniswap.buyPrice - ammPrices.sellPrice;
  const sellRateDiff = uniswap.sellPrice - ammPrices.buyPrice;

  log(`buy  ${formatUnits(uniswap.buyToAmount)} stETH for ${amount} WETH`);
  log(`sell ${amount} stETH for ${formatUnits(uniswap.sellToAmount)} WETH`);

  console.log(
    `\nwstETH/ETH 0.01% Uniswap V3 spot prices for swap size ${amount}`,
  );
  const buyGasCosts = gas ? `, ${uniswap.buyGas.toLocaleString()} gas` : "";
  const sellGasCosts = gas ? `, ${uniswap.sellGas.toLocaleString()} gas` : "";
  console.log(
    `buy    : ${formatUnits(uniswap.buyPrice, 18).padEnd(
      20,
    )} ${pair}, diff ${formatUnits(buyRateDiff, 14)} bps to ARM${buyGasCosts}`,
  );
  console.log(
    `mid    : ${formatUnits(uniswap.midPrice, 18).padEnd(20)} ${pair}`,
  );
  console.log(
    `sell   : ${formatUnits(uniswap.sellPrice, 18).padEnd(
      20,
    )} ${pair}, diff ${formatUnits(sellRateDiff, 14)} bps to ARM${sellGasCosts}`,
  );
  console.log(`spread : ${formatUnits(uniswap.spread, 14)} bps`);

  return uniswap;
};

const logFluidPrices = async (options, ammPrices) => {
  const { amount, pair, gas } = options;
  const fluid = await getFluidSpotPrices(options);
  const buyRateDiff = fluid.buyPrice - ammPrices.sellPrice;
  const sellRateDiff = fluid.sellPrice - ammPrices.buyPrice;

  log(`buy  ${formatUnits(fluid.buyToAmount)} stETH for ${amount} WETH`);
  log(`sell ${amount} stETH for ${formatUnits(fluid.sellToAmount)} WETH`);

  console.log(`\nwstETH/ETH FluidDex spot prices for swap size ${amount}`);
  const buyGasCosts = gas ? `, ${fluid.buyGas.toLocaleString()} gas` : "";
  const sellGasCosts = gas ? `, ${fluid.sellGas.toLocaleString()} gas` : "";
  console.log(
    `buy    : ${formatUnits(fluid.buyPrice, 18).padEnd(
      20,
    )} ${pair}, diff ${formatUnits(buyRateDiff, 14)} bps to ARM${buyGasCosts}`,
  );
  console.log(`mid    : ${formatUnits(fluid.midPrice, 18).padEnd(20)} ${pair}`);
  console.log(
    `sell   : ${formatUnits(fluid.sellPrice, 18).padEnd(
      20,
    )} ${pair}, diff ${formatUnits(sellRateDiff, 14)} bps to ARM${sellGasCosts}`,
  );
  console.log(`spread : ${formatUnits(fluid.spread, 14)} bps`);

  return fluid;
};

module.exports = {
  log1InchPrices,
  logArmPrices,
  logCurvePrices,
  logUniswapSpotPrices,
  logFluidPrices,
};
