const { formatUnits } = require("ethers");

const { resolveArmBase } = require("./arm");

const DEFAULT_ETHENA_AGGREGATOR_AMOUNT = 2000;

const hasAmountOverride = (amount) => amount !== undefined && amount !== null;

const readReserveLiquidity = (reserves) =>
  reserves.liquidityAssets ?? reserves[0];

const resolveEthenaAggregatorAmount = async ({
  arm,
  amount,
  log,
  blockTag = "latest",
  resolveArmBaseFn = resolveArmBase,
  defaultAmount = DEFAULT_ETHENA_AGGREGATOR_AMOUNT,
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
    log?.info?.(
      `Using default aggregator quote amount for legacy Ethena ARM: ${defaultAmount} USDe`,
    );
    return defaultAmount;
  }

  const reserves = await arm.getReserves(baseContext.baseAddress, {
    blockTag,
  });
  const liquidityAssets = readReserveLiquidity(reserves);

  if (liquidityAssets === 0n) {
    log?.info?.(
      "Skipping Ethena price update: no withdrawable USDe available in ARM or lending market",
    );
    return undefined;
  }

  const resolvedAmount = formatUnits(liquidityAssets, 18);
  log?.info?.(
    `Using ${resolvedAmount} USDe available in ARM and lending market as aggregator quote amount`,
  );
  return resolvedAmount;
};

module.exports = {
  DEFAULT_ETHENA_AGGREGATOR_AMOUNT,
  resolveEthenaAggregatorAmount,
};
