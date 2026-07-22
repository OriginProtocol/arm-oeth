const { formatUnits, parseUnits } = require("ethers");

const { resolveArmBase } = require("./arm");

const MIN_ETHENA_AGGREGATOR_AMOUNT = parseUnits("1000", 18); // 1,000 USDe

const hasAmountOverride = (amount) => amount !== undefined && amount !== null;

const readReserveLiquidity = (reserves) =>
  reserves.liquidityAssets ?? reserves[0];

const resolveEthenaAggregatorAmount = async ({
  arm,
  amount,
  log,
  blockTag = "latest",
  resolveArmBaseFn = resolveArmBase,
  minAmount = MIN_ETHENA_AGGREGATOR_AMOUNT,
}) => {
  if (hasAmountOverride(amount)) {
    log?.info?.(`Using configured aggregator quote amount: ${amount} USDe`);
    return amount;
  }

  const baseContext = await resolveArmBaseFn({
    arm,
    armName: "Ethena",
    base: "SUSDE",
    blockTag,
  });

  if (baseContext.version !== "multiBase") {
    const formattedMinAmount = formatUnits(minAmount, 18);
    log?.info?.(
      `Using minimum aggregator quote amount for legacy Ethena ARM: ${formattedMinAmount} USDe`,
    );
    return formattedMinAmount;
  }

  const reserves = await arm.getReserves(baseContext.baseAddress, {
    blockTag,
  });
  const liquidityAssets = readReserveLiquidity(reserves);

  if (liquidityAssets < minAmount) {
    log?.info?.(
      `Using minimum aggregator quote amount of ${formatUnits(minAmount, 18)} USDe; only ${formatUnits(liquidityAssets, 18)} USDe is withdrawable in ARM and lending market`,
    );
    return formatUnits(minAmount, 18);
  }

  const resolvedAmount = formatUnits(liquidityAssets, 18);
  log?.info?.(
    `Using ${resolvedAmount} USDe available in ARM and lending market as aggregator quote amount`,
  );
  return resolvedAmount;
};

module.exports = {
  MIN_ETHENA_AGGREGATOR_AMOUNT,
  resolveEthenaAggregatorAmount,
};
