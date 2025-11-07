const { formatUnits, parseUnits } = require("ethers");

const addresses = require("../utils/addresses");
const { get1InchPrices } = require("../utils/1Inch");
const { getCurvePrices } = require("../utils/curve");
const { getUniswapV3SpotPrices } = require("../utils/uniswap");
const { getSigner } = require("../utils/signers");
const { getFluidSpotPrices } = require("../utils/fluid");
const { mainnet } = require("../utils/addresses");

const log = require("../utils/logger")("task:markets");

const logArmPrices = async ({ blockTag, gas }, arm) => {
  console.log(`\nARM Prices`);
  // The rate of 1 WETH for stETH to 36 decimals from the perspective of the AMM. ie WETH/stETH
  // from the trader's perspective, this is the stETH/WETH buy price
  const rate0 = await arm.traderate0({ blockTag });

  // convert from WETH/stETH rate with 36 decimals to stETH/WETH rate with 18 decimals
  const sellPrice = BigInt(1e54) / BigInt(rate0);

  // The rate of 1 stETH for WETH to 36 decimals. ie stETH/WETH
  const rate1 = await arm.traderate1({ blockTag });
  // Convert back to 18 decimals
  const buyPrice = BigInt(rate1) / BigInt(1e18);

  const midPrice = (sellPrice + buyPrice) / 2n;

  const crossPrice = await arm.crossPrice({ blockTag });

  let buyGasCosts = "";
  let sellGasCosts = "";
  if (gas) {
    const signer = await getSigner();
    const amountBI = parseUnits("0.01", 18);
    const baseToken = await arm.baseAsset();
    const liquidityToken = await arm.liquidityAsset();
    try {
      const buyGas = await arm
        .connect(signer)
        [
          "swapExactTokensForTokens(address,address,uint256,uint256,address)"
        ].estimateGas(liquidityToken, baseToken, amountBI, 0, addresses.dead, {
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
        ].estimateGas(baseToken, liquidityToken, amountBI, 0, addresses.dead, {
          blockTag,
        });
      sellGasCosts = `, ${sellGas.toLocaleString()} gas`;
    } catch (e) {
      log(`Failed to estimate sell gas for swap: ${e.message}`);
    }
  }

  console.log(
    `sell   : ${formatUnits(sellPrice, 18).padEnd(20)} ${sellGasCosts}`,
  );
  if (crossPrice > sellPrice) {
    console.log(`cross  : ${formatUnits(crossPrice, 36).padEnd(20)}`);
    console.log(`mid    : ${formatUnits(midPrice, 18).padEnd(20)}`);
  } else {
    console.log(`mid    : ${formatUnits(midPrice, 18).padEnd(20)}`);
    console.log(`cross  : ${formatUnits(crossPrice, 18).padEnd(20)}`);
  }
  console.log(
    `buy    : ${formatUnits(buyPrice, 18).padEnd(20)} ${buyGasCosts}`,
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

const logMarketPrices = async ({
  marketPrices,
  armPrices,
  marketName,
  pair,
  amount,
  gas,
}) => {
  log(
    `buy  ${formatUnits(marketPrices.buyToAmount)} base assets for ${amount} liquidity assets`,
  );
  log(
    `sell ${amount} base assets for ${formatUnits(marketPrices.sellToAmount)} liquidity assets`,
  );

  console.log(`\n${marketName} prices for swap size ${amount}`);
  // Note market sell is from the trader's perspective while the ARM sell price is from the AMM's perspective
  const buyRateDiff = marketPrices.buyPrice - armPrices.sellPrice;
  const buyGasCosts = gas
    ? `, ${marketPrices.buyGas.toLocaleString()} gas`
    : "";
  console.log(
    `buy    : ${formatUnits(marketPrices.buyPrice, 18).padEnd(
      20,
    )} ${pair}, ${formatUnits(buyRateDiff, 14)} bps to ARM sell${buyGasCosts}`,
  );

  console.log(
    `mid    : ${formatUnits(marketPrices.midPrice, 18).padEnd(20)} ${pair}`,
  );

  // Note market buy is from the trader's perspective while the ARM buy price is from the AMM's perspective
  const sellRateDiff = marketPrices.sellPrice - armPrices.buyPrice;
  const armBuyToMarketSellDiff = marketPrices.buyPrice - armPrices.buyPrice;
  const sellGasCosts = gas
    ? `, ${marketPrices.sellGas.toLocaleString()} gas`
    : "";
  console.log(
    `sell   : ${formatUnits(marketPrices.sellPrice, 18).padEnd(
      20,
    )} ${pair}, ${formatUnits(sellRateDiff, 14).padEnd(
      17,
    )} bps from ARM buy, ${formatUnits(armBuyToMarketSellDiff, 14)} bps to ARM sell${sellGasCosts}`,
  );
  console.log(`spread : ${formatUnits(marketPrices.spread, 14)} bps`);
};

const log1InchPrices = async (options, armPrices) => {
  const { amount, assets, fee, chainId } = options;

  const oneInch = await get1InchPrices(amount, assets, fee, chainId);

  await logMarketPrices({
    ...options,
    marketPrices: oneInch,
    armPrices,
    marketName: "1Inch",
  });

  console.log(
    `\nBest buy : ${
      armPrices.sellPrice < oneInch.buyPrice ? "Origin" : "1Inch"
    }`,
  );
  console.log(
    `Best sell: ${armPrices.buyPrice > oneInch.sellPrice ? "Origin" : "1Inch"}`,
  );

  return oneInch;
};

const logCurvePrices = async (options, armPrices) => {
  const curve = await getCurvePrices(options);

  await logMarketPrices({
    ...options,
    marketPrices: curve,
    armPrices,
    marketName: options.poolName + " Curve",
  });

  return curve;
};

const logUniswapSpotPrices = async (options, armPrices, poolName) => {
  const uniswap = await getUniswapV3SpotPrices(options);

  await logMarketPrices({
    ...options,
    marketPrices: uniswap,
    armPrices,
    marketName: poolName + " Curve",
  });

  return uniswap;
};

const logFluidPrices = async (options, armPrices, poolName) => {
  const fluid = await getFluidSpotPrices(options);

  await logMarketPrices({
    ...options,
    marketPrices: fluid,
    armPrices,
    marketName: poolName + " Fluid",
  });

  return fluid;
};

const logWrappedEtherFiPrices = async ({ amount, armPrices }) => {
  const wrappedEtherFi = await ethers.getContractAt(
    ["function getEETHByWeETH(uint256) external view returns (uint256)"],
    mainnet.weETH,
  );
  const wrappedEtherFiScaled = parseUnits(amount.toString(), 18);
  const etherFiAmount =
    await wrappedEtherFi.getEETHByWeETH(wrappedEtherFiScaled);
  const wrapperPrice = (etherFiAmount * parseUnits("1")) / wrappedEtherFiScaled;
  console.log(
    `\nEther.fi wrapper (weETH) price: ${formatUnits(wrapperPrice, 18)} weETH/eETH`,
  );

  // Get weETH/WETH prices from 1Inch
  const oneInch = await get1InchPrices(
    amount,
    {
      liquid: mainnet.WETH,
      base: mainnet.weETH,
    },
    10n,
    1,
  );
  const adjustedMarketPrices = {
    ...oneInch,
    buyPrice: (oneInch.buyPrice * parseUnits("1")) / wrapperPrice,
    sellPrice: (oneInch.sellPrice * parseUnits("1")) / wrapperPrice,
    midPrice: (oneInch.midPrice * parseUnits("1")) / wrapperPrice,
  };

  await logMarketPrices({
    amount,
    marketPrices: adjustedMarketPrices,
    armPrices,
    pair: "weETH->eUSD->WETH",
    marketName: "1Inch wrapped eETH (weETH) prices adjusted back to eETH",
  });

  console.log(
    `\nBest buy : ${
      armPrices.sellPrice < adjustedMarketPrices.buyPrice ? "Origin" : "1Inch"
    }`,
  );
  console.log(
    `Best sell: ${armPrices.buyPrice > adjustedMarketPrices.sellPrice ? "Origin" : "1Inch"}`,
  );
};

module.exports = {
  log1InchPrices,
  logArmPrices,
  logCurvePrices,
  logUniswapSpotPrices,
  logFluidPrices,
  logWrappedEtherFiPrices,
};
