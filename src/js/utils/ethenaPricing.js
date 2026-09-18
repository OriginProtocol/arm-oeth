const { formatUnits, parseUnits } = require("ethers");

const { adapterContract, resolveArmBase } = require("./arm");
const {
  computeTranche,
  computeUtilisationBps,
  ladderDiscountBps100,
  ladderMaxBuyPrice,
  parseLadder,
  resolveQuoteAmount,
} = require("./tranchePricing");

const log = require("./logger")("task:prices:tranche");

const MIN_ETHENA_AGGREGATOR_AMOUNT = parseUnits("1000", 18); // 1,000 USDe

/**
 * Compute the tranche pricing overrides for the Ethena ARM: the buy liquidity
 * limit, the aggregator quote size and the ladder-driven max buy price.
 *
 * All three are derived from the same block so the cap refresh decision in
 * setPrices compares like with like.
 *
 * @param {object} params
 * @param {import("ethers").Contract} params.arm Ethena ARM contract (full ABI)
 * @param {string} [params.armName="Ethena"]
 * @param {string} [params.base="SUSDE"]
 * @param {number|string} [params.blockTag="latest"] block to read state at
 * @param {number} params.tranchePctBps share of liquidity per tranche, 3500 = 35%
 * @param {bigint} params.trancheStepWei rounding step in liquidity wei, eg 25,000e18
 * @param {bigint} params.trancheMinWei minimum tranche in liquidity wei, eg 25,000e18
 * @param {string} params.ladder "u%:bps,..." eg "50:2.5,70:3.5,85:5"
 * @param {number} params.ladderStepBps100 quantisation of the ladder, 25 = 0.25 bps
 * @param {number|string} [params.maxBuyPrice] absolute guard, eg 0.99985; the
 *   tighter of the guard and the ladder is used
 * @param {bigint} [params.minQuoteAmount] floor for the aggregator quote size
 * @param {function} [params.resolveArmBaseFn] test hook
 * @param {function} [params.adapterContractFn] test hook
 * @returns {Promise<{buyAmount: bigint, amount: string, maxBuyPrice: string,
 *   utilisationBps: number, ladderBps100: number, tranche: bigint,
 *   liquidityAssets: bigint, totalAssets: bigint}>}
 *   `buyAmount`, `amount` and `maxBuyPrice` are in the shapes setPrices expects.
 */
const resolveEthenaTranche = async ({
  arm,
  armName = "Ethena",
  base = "SUSDE",
  blockTag = "latest",
  tranchePctBps,
  trancheStepWei,
  trancheMinWei,
  ladder,
  ladderStepBps100,
  maxBuyPrice,
  minQuoteAmount = MIN_ETHENA_AGGREGATOR_AMOUNT,
  resolveArmBaseFn = resolveArmBase,
  adapterContractFn = adapterContract,
}) => {
  const knots = parseLadder(ladder);

  const baseContext = await resolveArmBaseFn({ arm, armName, base, blockTag });
  if (baseContext.version !== "multiBase") {
    throw new Error(`Tranche pricing requires a multi-base ${armName} ARM`);
  }
  const { baseAddress, config } = baseContext;
  const baseDecimals = Number(config.baseAssetDecimals ?? 18);

  const reserves = await arm.getReserves(baseAddress, { blockTag });
  const liquidityAssets = reserves.liquidityAssets ?? reserves[0];
  const totalAssets = await arm.totalAssets({ blockTag });

  const utilisationBps = computeUtilisationBps(liquidityAssets, totalAssets);
  const ladderBps100 = ladderDiscountBps100(
    utilisationBps,
    knots,
    ladderStepBps100,
  );
  const ladderPrice = ladderMaxBuyPrice(ladderBps100);

  const guardPrice =
    maxBuyPrice === undefined || maxBuyPrice === null
      ? undefined
      : parseUnits(maxBuyPrice.toString(), 36);
  const guardIsTighter = guardPrice !== undefined && guardPrice < ladderPrice;
  const maxPrice = guardIsTighter ? guardPrice : ladderPrice;

  const tranche = computeTranche({
    liquidityAssets,
    pctBps: tranchePctBps,
    stepWei: trancheStepWei,
    minWei: trancheMinWei,
  });
  const quoteAssets = resolveQuoteAmount(tranche, minQuoteAmount);
  // The wrapped pricing path quotes in base asset units (sUSDe), so convert
  // the tranche in liquidity assets (USDe) to shares.
  const adapter = await adapterContractFn(config.adapter, arm.runner);
  const quoteShares = await adapter.convertToShares(quoteAssets, { blockTag });

  log(`Tranche pricing at block ${blockTag}:`);
  log(`liquidity assets   : ${formatUnits(liquidityAssets, 18)}`);
  log(`total assets       : ${formatUnits(totalAssets, 18)}`);
  log(`utilisation        : ${(utilisationBps / 100).toFixed(2)}%`);
  log(`ladder discount    : ${(ladderBps100 / 100).toFixed(2)} bps`);
  log(`ladder max price   : ${formatUnits(ladderPrice, 36)}`);
  log(`tranche            : ${formatUnits(tranche, 18)}`);
  log(
    `quote size         : ${formatUnits(quoteAssets, 18)} = ${formatUnits(quoteShares, baseDecimals)} shares`,
  );

  if (guardIsTighter) {
    console.warn(
      `Max buy price guard ${maxBuyPrice} is tighter than the ladder price ${formatUnits(ladderPrice, 36)}; the ladder is not in control`,
    );
  }
  if (maxPrice >= config.crossPrice) {
    console.warn(
      `Ladder max buy price ${formatUnits(maxPrice, 36)} is not below the cross price ${formatUnits(config.crossPrice, 36)}; setPrices will clamp it`,
    );
  }

  return {
    buyAmount: tranche,
    amount: formatUnits(quoteShares, baseDecimals),
    maxBuyPrice: formatUnits(maxPrice, 36),
    utilisationBps,
    ladderBps100,
    tranche,
    liquidityAssets,
    totalAssets,
  };
};

module.exports = {
  MIN_ETHENA_AGGREGATOR_AMOUNT,
  resolveEthenaTranche,
};
