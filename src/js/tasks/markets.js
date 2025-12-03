const { formatUnits, parseUnits } = require("ethers");

const addresses = require("../utils/addresses");
const { get1InchPrices } = require("../utils/1Inch");
const { getCurvePrices } = require("../utils/curve");
const { getKyberPrices } = require("../utils/kyber");
const { getUniswapV3SpotPrices } = require("../utils/uniswap");
const { getSigner } = require("../utils/signers");
const { getFluidSpotPrices } = require("../utils/fluid");
const { mainnet } = require("../utils/addresses");
const { resolveAddress } = require("../utils/assets");

const log = require("../utils/logger")("task:markets");

const snapMarket = async ({
  amount,
  base,
  liquid,
  wrapped,
  days,
  fee1Inch,
  oneInch,
  kyber,
}) => {
  const baseAddress = await resolveAddress(base.toUpperCase());
  const liquidAddress = await resolveAddress(liquid.toUpperCase());
  const assets = {
    liquid: liquidAddress,
    base: baseAddress,
  };

  let wrapPrice;
  if (wrapped) {
    // Assume the wrapped base asset is ERC-4626
    wrapPrice = await convertToAsset(baseAddress, amount);

    console.log(
      `\nWrapped price: ${formatUnits(wrapPrice, 18)} ${base}/${liquid}`,
    );
  }

  const pair = wrapped ? `unwrapped ${base}->${liquid}` : `${base}/${liquid}`;
  if (oneInch) {
    const fee = BigInt(fee1Inch);

    const chainId = await (await ethers.provider.getNetwork()).chainId;
    const marketPrices = await log1InchPrices({
      amount,
      assets,
      fee,
      pair,
      chainId,
      wrapPrice,
    });

    if (days) {
      logDiscount(marketPrices.sellPrice, days);
    }
  }

  if (kyber) {
    const marketPrices = await logKyberPrices({
      amount,
      days,
      assets,
      pair,
      wrapPrice,
    });

    if (days) {
      logDiscount(marketPrices.sellPrice, days);
    }
  }
};

const convertToAsset = async (vaultAddress, amount) => {
  const vault = await ethers.getContractAt("IERC4626", vaultAddress);
  const assetAmount = await vault.convertToAssets(
    parseUnits(amount.toString(), 18),
  );
  const assetPrice =
    (assetAmount * parseUnits("1")) / parseUnits(amount.toString(), 18);
  return assetPrice;
};

const logDiscountsOverDays = (marketPrice, daysArray) => {
  // take 80% of the discount to cover the 20% fee
  const discount = BigInt(1e18) - marketPrice;
  const discountPostFee = (discount * 8n) / 10n;
  console.log(
    `\nYield on ${formatUnits(
      discountPostFee * 10000n,
      18,
    )} bps discount after 20% fee`,
  );

  let output = "";
  for (const days of daysArray) {
    const discountAPY =
      (discountPostFee * 36500n) / BigInt(days) / parseUnits("1", 16);
    output += `${days} days ${formatUnits(discountAPY, 2)}%, `;
  }
  output = output.slice(0, -2); // remove trailing comma and space
  output += " APY";

  console.log(output);
};

const logDiscount = (marketPrice, days) => {
  const discount = BigInt(1e18) - marketPrice;
  // take 80% of the discount to cover the 20% fee
  const discountPostFee = (discount * 8n) / 10n;
  const discountAPY = (discountPostFee * 365n) / BigInt(days);
  console.log(
    `Discount over ${days} days after 20% fee: ${formatUnits(
      discountPostFee * 10000n,
      18,
    )} bps, ${formatUnits(discountAPY * 100n, 18)}% APY`,
  );
};

const logArmPrices = async ({ blockTag, gas, days }, arm) => {
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

  if (days) {
    logDiscount(buyPrice, days);
  } else {
    logDiscountsOverDays(buyPrice, [1, 2, 3, 4, 5, 7]);
  }

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
  let armDiff = "";
  if (armPrices) {
    // Note market sell is from the trader's perspective while the ARM sell price is from the AMM's perspective
    const buyRateDiff = marketPrices.buyPrice - armPrices.sellPrice;
    const armBuyToMarketSellDiff = marketPrices.buyPrice - armPrices.buyPrice;
    const buyGasCosts = gas
      ? `, ${marketPrices.buyGas.toLocaleString()} gas`
      : "";
    armDiff = `, ${formatUnits(armBuyToMarketSellDiff, 14)} bps from ARM buy, ${formatUnits(buyRateDiff, 14)} bps from ARM sell${buyGasCosts}`;
  }
  console.log(
    `buy    : ${formatUnits(marketPrices.buyPrice, 18).padEnd(
      20,
    )} ${pair}${armDiff}`,
  );

  console.log(
    `mid    : ${formatUnits(marketPrices.midPrice, 18).padEnd(20)} ${pair}`,
  );

  // Note market buy is from the trader's perspective while the ARM buy price is from the AMM's perspective
  if (armPrices) {
    const sellRateDiff = marketPrices.sellPrice - armPrices.buyPrice;
    const sellGasCosts = gas
      ? `, ${marketPrices.sellGas.toLocaleString()} gas`
      : "";
    armDiff = `, ${formatUnits(sellRateDiff, 14).padEnd(
      17,
    )} bps from ARM buy${sellGasCosts}`;
  }
  console.log(
    `sell   : ${formatUnits(marketPrices.sellPrice, 18).padEnd(
      20,
    )} ${pair}${armDiff}`,
  );
  console.log(`spread : ${formatUnits(marketPrices.spread, 14)} bps`);
};

const log1InchPrices = async (options, armPrices) => {
  const { amount, assets, fee, chainId, wrapPrice } = options;

  const marketPrices = await get1InchPrices(amount, assets, fee, chainId);

  if (wrapPrice) {
    unwrapPrices(marketPrices, wrapPrice);
  }

  await logMarketPrices({
    ...options,
    marketPrices,
    armPrices,
    marketName: "1Inch",
  });

  if (armPrices === undefined) return marketPrices;

  console.log(
    `\nBest buy : ${
      armPrices.sellPrice < marketPrices.buyPrice ? "Origin" : "1Inch"
    }`,
  );
  console.log(
    `Best sell: ${armPrices.buyPrice > marketPrices.sellPrice ? "Origin" : "1Inch"}`,
  );

  return marketPrices;
};

const logKyberPrices = async (options, armPrices) => {
  const { amount, assets, wrapPrice } = options;

  const marketPrices = await getKyberPrices(amount, assets);

  if (wrapPrice) {
    unwrapPrices(marketPrices, wrapPrice);
  }

  await logMarketPrices({
    ...options,
    marketPrices,
    armPrices,
    marketName: "Kyber",
  });

  if (armPrices === undefined) return marketPrices;

  console.log(
    `\nBest buy : ${
      armPrices.sellPrice < marketPrices.buyPrice ? "Origin" : "Kyber"
    }`,
  );
  console.log(
    `Best sell: ${armPrices.buyPrice > marketPrices.sellPrice ? "Origin" : "Kyber"}`,
  );

  return marketPrices;
};

const unwrapPrices = (marketPrices, wrapPrice) => {
  // Adjust prices back to unwrapped base asset
  marketPrices.buyPrice = (marketPrices.buyPrice * parseUnits("1")) / wrapPrice;
  marketPrices.sellPrice =
    (marketPrices.sellPrice * parseUnits("1")) / wrapPrice;
  marketPrices.midPrice = (marketPrices.midPrice * parseUnits("1")) / wrapPrice;
  marketPrices.buyToAmount =
    (marketPrices.buyToAmount * parseUnits("1")) / wrapPrice;
  marketPrices.sellToAmount =
    (marketPrices.sellToAmount * parseUnits("1")) / wrapPrice;
};

const logCurvePrices = async (options, armPrices) => {
  const marketPrices = await getCurvePrices(options);

  await logMarketPrices({
    ...options,
    marketPrices,
    armPrices,
    marketName: options.poolName + " Curve",
  });

  return marketPrices;
};

const logUniswapSpotPrices = async (options, armPrices, poolName) => {
  const marketPrices = await getUniswapV3SpotPrices(options);

  await logMarketPrices({
    ...options,
    marketPrices,
    armPrices,
    marketName: poolName + " Curve",
  });

  return marketPrices;
};

const logFluidPrices = async (options, armPrices, poolName) => {
  const marketPrices = await getFluidSpotPrices(options);

  await logMarketPrices({
    ...options,
    marketPrices,
    armPrices,
    marketName: poolName + " Fluid",
  });

  return marketPrices;
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
  convertToAsset,
  snapMarket,
  log1InchPrices,
  logKyberPrices,
  logArmPrices,
  logCurvePrices,
  logUniswapSpotPrices,
  logFluidPrices,
  logWrappedEtherFiPrices,
};
