const { formatUnits } = require("ethers");

const { resolveArmBase } = require("./arm");

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

  if (liquidityAssets === 0n) {
    log?.info?.(
      "Skipping USD price update: no withdrawable USDC available in ARM or lending market",
    );
    return undefined;
  }

  const resolvedAmount = formatUnits(liquidityAssets, 6);
  log?.info?.(
    `Using ${resolvedAmount} USDC available in ARM and lending market as aggregator quote amount`,
  );
  return resolvedAmount;
};

module.exports = {
  resolveUsdAggregatorAmount,
};
