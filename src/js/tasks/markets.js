const { formatUnits, isAddress, parseUnits } = require("ethers");

const addresses = require("../utils/addresses");
const { get1InchPrices } = require("../utils/1Inch");
const { getCurvePrices } = require("../utils/curve");
const { getKyberPrices } = require("../utils/kyber");
const { getUniswapV3SpotPrices } = require("../utils/uniswap");
const { getSigner } = require("../utils/signers");
const { getFluidSpotPrices } = require("../utils/fluid");
const { mainnet } = require("../utils/addresses");
const { resolveAddress } = require("../utils/assets");
const { convertToAsset, convertReth } = require("../utils/pricing");

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
    const signer = await getSigner();
    if (base.toUpperCase() === "RETH") {
      wrapPrice = await convertReth(amount, signer);
    } else {
      // Assume the wrapped base asset is ERC-4626
      wrapPrice = await convertToAsset(baseAddress, amount, signer);
    }
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

  await log1InchRouteSummary(marketPrices.buyQuote, "buy");
  await log1InchRouteSummary(marketPrices.sellQuote, "sell");

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

const formatOneInchProtocolSummary = (protocols) => {
  if (!Array.isArray(protocols) || protocols.length === 0) {
    return "unknown-protocol";
  }

  return protocols
    .map((protocol) => {
      const name = protocol?.name ?? "unknown";
      const part = protocol?.part;
      const partText =
        typeof part === "number" || typeof part === "string"
          ? ` ${part}%`
          : "";
      return `${name}${partText}`;
    })
    .join(", ");
};

const get1InchHopKey = (fromToken, hop) => {
  const normalizedFromToken =
    typeof fromToken === "string" ? fromToken.toLowerCase() : "unknown-from";
  const normalizedToToken =
    typeof hop?.dst === "string" ? hop.dst.toLowerCase() : "unknown-to";
  const part = hop?.part ?? "unknown-part";
  const protocolKey = Array.isArray(hop?.protocols)
    ? hop.protocols
        .map((protocol) => `${protocol?.name ?? "unknown"}:${protocol?.part ?? "n/a"}`)
        .join("|")
    : "unknown-protocols";

  return `${normalizedFromToken}->${normalizedToToken}:${part}:${protocolKey}`;
};

const get1InchRouteHops = (protocols) => {
  if (!Array.isArray(protocols)) return [];

  const dedupedRouteHops = [];
  const seenHopKeys = new Set();

  for (const routeNode of protocols) {
    const fromToken = routeNode?.token;
    if (!Array.isArray(routeNode?.hops)) continue;

    for (const hop of routeNode.hops) {
      if (!hop || typeof hop !== "object") continue;
      const hopKey = get1InchHopKey(fromToken, hop);
      if (seenHopKeys.has(hopKey)) continue;
      dedupedRouteHops.push({
        fromToken,
        toToken: hop.dst,
        part: hop.part,
        protocols: hop.protocols,
      });
      seenHopKeys.add(hopKey);
    }
  }

  if (dedupedRouteHops.length === 0) return [];

  const rootToken =
    typeof protocols[0]?.token === "string" ? protocols[0].token.toLowerCase() : null;
  const orderedRouteHops = [];
  const used = new Set();

  const appendWithChildren = (parentIndex, isSubsequentHop) => {
    if (used.has(parentIndex)) return;
    used.add(parentIndex);

    const parentHop = dedupedRouteHops[parentIndex];
    orderedRouteHops.push({
      ...parentHop,
      isSubsequentHop,
    });

    if (typeof parentHop.toToken !== "string") return;
    const parentToToken = parentHop.toToken.toLowerCase();

    for (let i = 0; i < dedupedRouteHops.length; i += 1) {
      if (used.has(i)) continue;
      const childFromToken =
        typeof dedupedRouteHops[i].fromToken === "string"
          ? dedupedRouteHops[i].fromToken.toLowerCase()
          : null;
      if (childFromToken === parentToToken) {
        appendWithChildren(i, true);
      }
    }
  };

  for (let i = 0; i < dedupedRouteHops.length; i += 1) {
    const fromToken =
      typeof dedupedRouteHops[i].fromToken === "string"
        ? dedupedRouteHops[i].fromToken.toLowerCase()
        : null;
    if (rootToken !== null && fromToken === rootToken) {
      appendWithChildren(i, false);
    }
  }

  for (let i = 0; i < dedupedRouteHops.length; i += 1) {
    appendWithChildren(i, false);
  }

  return orderedRouteHops;
};

const format1InchRouteLeg = async (hop, index) => {
  const fromToken = await formatRouteToken(hop?.fromToken);
  const toToken = await formatRouteToken(hop?.toToken);
  const splitText =
    typeof hop?.part === "number" || typeof hop?.part === "string"
      ? `${hop.part}%`
      : "n/a";
  const detailsIndent = hop?.isSubsequentHop ? "    " : "";
  const protocols = formatOneInchProtocolSummary(hop?.protocols);

  return `  ${index}. ${detailsIndent}${splitText.padStart(8)} ${fromToken} -> ${toToken} via ${protocols}`;
};

const log1InchRouteSummary = async (quote, sideLabel) => {
  console.log(`\n1Inch ${sideLabel} route:`);
  const routeHops = get1InchRouteHops(quote?.protocols);

  if (routeHops.length === 0) {
    console.log("  route unavailable");
    return;
  }

  for (let i = 0; i < routeHops.length; i += 1) {
    console.log(await format1InchRouteLeg(routeHops[i], i + 1));
  }
};

const shortAddress = (value) => {
  if (typeof value !== "string" || !value.startsWith("0x") || value.length < 10)
    return value;
  return `${value.slice(0, 6)}...${value.slice(-4)}`;
};

const KYBER_ROUTE_TOKENS = {
  [addresses.ETH.toLowerCase()]: "WETH",
  [addresses.mainnet.WETH.toLowerCase()]: "WETH",
  [addresses.mainnet.stETH.toLowerCase()]: "stETH",
  [addresses.mainnet.wstETH.toLowerCase()]: "wstETH",
  [addresses.mainnet.eETH.toLowerCase()]: "eETH",
  [addresses.mainnet.weETH.toLowerCase()]: "weETH",
  [addresses.mainnet.sUSDe.toLowerCase()]: "sUSDe",
  [addresses.mainnet.USDe.toLowerCase()]: "USDe",
  [addresses.mainnet.USDC.toLowerCase()]: "USDC",
  [addresses.mainnet.USDT.toLowerCase()]: "USDT",
};

const tokenSymbolCache = new Map(Object.entries(KYBER_ROUTE_TOKENS));
const tokenDecimalsCache = new Map();

const scaleAmountTo18 = (amount, decimals) => {
  if (amount === null || amount === undefined) return null;
  const parsedAmount = toBigIntOrNull(amount);
  if (parsedAmount === null) return null;

  if (decimals === 18) return parsedAmount;
  if (decimals > 18) {
    return parsedAmount / 10n ** BigInt(decimals - 18);
  }
  return parsedAmount * 10n ** BigInt(18 - decimals);
};

const resolveTokenSymbol = async (tokenAddress) => {
  const normalizedAddress = tokenAddress.toLowerCase();
  if (tokenSymbolCache.has(normalizedAddress)) {
    return tokenSymbolCache.get(normalizedAddress);
  }

  let symbol = shortAddress(tokenAddress);
  try {
    const token = await ethers.getContractAt(
      ["function symbol() external view returns (string)"],
      tokenAddress,
    );
    const tokenSymbol = await token.symbol();
    if (typeof tokenSymbol === "string" && tokenSymbol.length > 0) {
      symbol = tokenSymbol;
    }
  } catch {
    // Use short address fallback when symbol lookup fails.
  }

  tokenSymbolCache.set(normalizedAddress, symbol);
  return symbol;
};

const resolveTokenDecimals = async (tokenAddress) => {
  const normalizedAddress = tokenAddress.toLowerCase();
  if (tokenDecimalsCache.has(normalizedAddress)) {
    return tokenDecimalsCache.get(normalizedAddress);
  }

  let decimals = null;
  try {
    const token = await ethers.getContractAt(
      ["function decimals() external view returns (uint8)"],
      tokenAddress,
    );
    decimals = Number(await token.decimals());
  } catch {
    // Keep null if token decimals cannot be fetched.
  }

  tokenDecimalsCache.set(normalizedAddress, decimals);
  return decimals;
};

const formatRouteToken = async (token) => {
  if (typeof token === "string") {
    if (!isAddress(token)) {
      return token;
    }
    return resolveTokenSymbol(token);
  }
  if (token && typeof token === "object") {
    if (typeof token.symbol === "string" && token.symbol.length > 0) {
      return token.symbol;
    }
    if (typeof token.address === "string") {
      return formatRouteToken(token.address);
    }
  }
  return "unknown-token";
};

const getTokenAddress = (token) => {
  if (typeof token === "string" && isAddress(token)) return token;
  if (
    token &&
    typeof token === "object" &&
    typeof token.address === "string" &&
    isAddress(token.address)
  ) {
    return token.address;
  }
  return null;
};

const toBigIntOrNull = (value) => {
  if (typeof value === "bigint") return value;
  if (typeof value !== "string" && typeof value !== "number") return null;
  try {
    return BigInt(value);
  } catch {
    return null;
  }
};

const formatKyberRouteLeg = async (
  swap,
  totalIn,
  totalInDecimals,
  index,
  isSubsequentHop,
) => {
  let splitText = "n/a";
  const swapTokenInAddress = getTokenAddress(swap?.tokenIn);
  let swapTokenInDecimals = null;
  if (swapTokenInAddress) {
    swapTokenInDecimals = await resolveTokenDecimals(swapTokenInAddress);
  }

  const normalizedSwapAmount = scaleAmountTo18(
    swap?.swapAmount,
    swapTokenInDecimals,
  );
  const normalizedTotalIn = scaleAmountTo18(totalIn, totalInDecimals);
  if (
    normalizedSwapAmount !== null &&
    normalizedTotalIn !== null &&
    normalizedTotalIn > 0n
  ) {
    const splitBps = (normalizedSwapAmount * 10000n) / normalizedTotalIn;
    splitText = `${formatUnits(splitBps, 2)}%`;
  }

  const tokenIn = await formatRouteToken(swap?.tokenIn);
  const tokenOut = await formatRouteToken(swap?.tokenOut);

  const exchange = swap?.exchange ?? "unknown-exchange";
  const pool = swap?.pool ?? "unknown-pool";
  const poolText =
    typeof pool === "string" ? shortAddress(pool) : "unknown-pool";

  const detailsIndent = isSubsequentHop ? "    " : "";
  return `  ${index}. ${detailsIndent}${splitText.padStart(8)} ${tokenIn} -> ${tokenOut} via ${exchange} (${poolText})`;
};

const getKyberRouteSwaps = (route) => {
  if (!Array.isArray(route)) return [];

  const swaps = [];
  for (const leg of route) {
    if (Array.isArray(leg)) {
      for (let i = 0; i < leg.length; i += 1) {
        const swap = leg[i];
        if (swap && typeof swap === "object") {
          swaps.push({ swap, isSubsequentHop: i > 0 });
        }
      }
      continue;
    }

    if (Array.isArray(leg?.swaps)) {
      for (let i = 0; i < leg.swaps.length; i += 1) {
        const swap = leg.swaps[i];
        if (swap && typeof swap === "object") {
          swaps.push({ swap, isSubsequentHop: i > 0 });
        }
      }
      continue;
    }

    if (leg && typeof leg === "object") {
      swaps.push({ swap: leg, isSubsequentHop: false });
    }
  }
  return swaps;
};

const logKyberRouteSummary = async (quote, sideLabel) => {
  console.log(`\nKyber ${sideLabel} route:`);

  const routeSwaps = getKyberRouteSwaps(quote?.route);
  if (routeSwaps.length === 0) {
    console.log("  route unavailable");
    return;
  }

  const totalInTokenAddress = getTokenAddress(quote?.tokenIn);
  const totalInDecimals = totalInTokenAddress
    ? await resolveTokenDecimals(totalInTokenAddress)
    : null;
  for (let i = 0; i < routeSwaps.length; i += 1) {
    const { swap, isSubsequentHop } = routeSwaps[i];
    console.log(
      await formatKyberRouteLeg(
        swap,
        quote?.amountIn,
        totalInDecimals,
        i + 1,
        isSubsequentHop,
      ),
    );
  }
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

  await logKyberRouteSummary(marketPrices.buyQuote, "buy");
  await logKyberRouteSummary(marketPrices.sellQuote, "sell");

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
  snapMarket,
  log1InchPrices,
  logKyberPrices,
  logArmPrices,
  logCurvePrices,
  logUniswapSpotPrices,
  logFluidPrices,
  logWrappedEtherFiPrices,
};
