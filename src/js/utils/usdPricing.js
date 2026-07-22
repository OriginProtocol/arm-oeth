const { formatUnits, parseUnits } = require("ethers");

const { resolveArmBase } = require("./arm");

// Below this the aggregators return unusable quotes: dust amounts get
// quantized into garbage price ratios and Kyber rejects the request outright
const MIN_USD_AGGREGATOR_AMOUNT = parseUnits("1000", 6); // 1,000 USDC

const hasAmountOverride = (amount) => amount !== undefined && amount !== null;

const readReserveLiquidity = (reserves) =>
  reserves.liquidityAssets ?? reserves[0];

const resolveUsdAggregatorAmount = async ({
  arm,
  amount,
  log,
  blockTag = "latest",
  resolveArmBaseFn = resolveArmBase,
}) => {
  if (hasAmountOverride(amount)) {
    log?.info?.(`Using configured aggregator quote amount: ${amount} USDC`);
    return amount;
  }

  // The liquidity reserves are shared across the base assets so any
  // configured base can be used to resolve them
  const baseContext = await resolveArmBaseFn({
    arm,
    armName: "USD",
    base: "PYUSD",
    blockTag,
  });

  const reserves = await arm.getReserves(baseContext.baseAddress, {
    blockTag,
  });
  const liquidityAssets = readReserveLiquidity(reserves);

  if (liquidityAssets < MIN_USD_AGGREGATOR_AMOUNT) {
    log?.info?.(
      `Using minimum aggregator quote amount of ${formatUnits(MIN_USD_AGGREGATOR_AMOUNT, 6)} USDC; only ${formatUnits(liquidityAssets, 6)} USDC is withdrawable in ARM and lending market`,
    );
    return formatUnits(MIN_USD_AGGREGATOR_AMOUNT, 6);
  }

  const resolvedAmount = formatUnits(liquidityAssets, 6);
  log?.info?.(
    `Using ${resolvedAmount} USDC available in ARM and lending market as aggregator quote amount`,
  );
  return resolvedAmount;
};

module.exports = {
  MIN_USD_AGGREGATOR_AMOUNT,
  resolveUsdAggregatorAmount,
};
