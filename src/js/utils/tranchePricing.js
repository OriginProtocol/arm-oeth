/**
 * Pure helpers for tranche pricing with a utilisation ladder.
 *
 * The ARM quotes one buy price for a tranche S of its liquidity: S is both the
 * on-chain `buyLiquidityRemaining` cap and the size of the aggregator quote.
 * The ladder gives the minimum discount below NAV the ARM charges as a function
 * of utilisation u = 1 - available liquidity / total assets.
 *
 * Units used throughout (integers only, no floats for on-chain values):
 * - utilisation in basis points of total assets: 0 = idle, 10000 = fully deployed
 * - discount in hundredths of a basis point (bps100): 250 = 2.5 bps, 500 = 5 bps
 * - token amounts as BigInt in the token's smallest unit (wei)
 * - prices as BigInt scaled to 1e36 (ARM PRICE_SCALE)
 */

const PRICE_SCALE = 10n ** 36n;
// 1 bps = 1e32 at 36 decimals, so 0.01 bps = 1e30
const BPS100_PRICE_UNIT = 10n ** 30n;
const UTILISATION_SCALE = 10000n;

/**
 * Parse a decimal string/number into an integer after scaling.
 * Rejects values that need more precision than the scale allows.
 * @example scaledInt("2.5", 100, "bps") = 250; scaledInt("50", 100, "u") = 5000
 */
const scaledInt = (value, scale, label) => {
  const number = Number(value);
  if (typeof value === "string" && value.trim() === "") {
    throw new Error(`Missing ${label} value`);
  }
  if (!Number.isFinite(number)) {
    throw new Error(`Invalid ${label} value "${value}"`);
  }
  const scaled = number * scale;
  const rounded = Math.round(scaled);
  if (Math.abs(scaled - rounded) > 1e-6) {
    throw new Error(
      `${label} value "${value}" has more precision than supported (1/${scale})`,
    );
  }
  return rounded;
};

/**
 * Parse a ladder definition "u%:bps,u%:bps,..." into sorted knots.
 * @param {string} ladder eg "50:2.5,70:3.5,85:5" = 2.5 bps below 50% utilisation,
 *   3.5 bps at 70%, 5 bps from 85% up
 * @returns {{uBps: number, bps100: number}[]} knots with strictly increasing uBps
 */
const parseLadder = (ladder) => {
  if (typeof ladder !== "string" || ladder.trim() === "") {
    throw new Error(
      `Invalid ladder "${ladder}": expected "u%:bps,u%:bps", eg "50:2.5,70:3.5,85:5"`,
    );
  }

  const knots = ladder.split(",").map((pair) => {
    const parts = pair.split(":").map((part) => part.trim());
    if (parts.length !== 2) {
      throw new Error(`Invalid ladder knot "${pair}": expected "u%:bps"`);
    }
    const uBps = scaledInt(parts[0], 100, "ladder utilisation");
    const bps100 = scaledInt(parts[1], 100, "ladder discount");
    if (uBps < 0 || uBps > Number(UTILISATION_SCALE)) {
      throw new Error(
        `Invalid ladder utilisation "${parts[0]}": must be between 0 and 100`,
      );
    }
    if (bps100 < 0) {
      throw new Error(`Invalid ladder discount "${parts[1]}": must be >= 0`);
    }
    return { uBps, bps100 };
  });

  for (let i = 1; i < knots.length; i++) {
    if (knots[i].uBps <= knots[i - 1].uBps) {
      throw new Error(
        `Invalid ladder "${ladder}": utilisation levels must be strictly increasing`,
      );
    }
  }

  return knots;
};

/**
 * Discount (bps100) for a utilisation level: linear interpolation between knots,
 * flat outside the first and last knot, then rounded to the nearest multiple of
 * `stepBps100` (ties round up).
 * @param {number} uBps utilisation, 0..10000
 * @param {{uBps: number, bps100: number}[]} knots from parseLadder
 * @param {number} stepBps100 quantisation step, eg 25 = 0.25 bps
 * @example u=6000 with knots 50:2.5,70:3.5 -> 300 (3.0 bps)
 */
const ladderDiscountBps100 = (uBps, knots, stepBps100 = 25) => {
  if (!Array.isArray(knots) || knots.length === 0) {
    throw new Error("Ladder must have at least one knot");
  }
  if (!Number.isInteger(stepBps100) || stepBps100 <= 0) {
    throw new Error(
      `Invalid ladder step ${stepBps100}: must be a positive integer`,
    );
  }

  let raw;
  const first = knots[0];
  const last = knots[knots.length - 1];
  if (uBps <= first.uBps) {
    raw = first.bps100;
  } else if (uBps >= last.uBps) {
    raw = last.bps100;
  } else {
    let i = 1;
    while (knots[i].uBps < uBps) i++;
    const lo = knots[i - 1];
    const hi = knots[i];
    raw =
      lo.bps100 +
      ((hi.bps100 - lo.bps100) * (uBps - lo.uBps)) / (hi.uBps - lo.uBps);
  }

  return Math.floor(raw / stepBps100 + 0.5) * stepBps100;
};

/**
 * Buy price (36 decimals) for a discount below NAV, with NAV = 1 in the
 * ARM's "per share" price space.
 * @param {number} bps100 eg 250 = 2.5 bps -> 0.99975e36
 */
const ladderMaxBuyPrice = (bps100) =>
  PRICE_SCALE - BigInt(bps100) * BPS100_PRICE_UNIT;

/**
 * Utilisation in basis points: share of total assets that is not available as
 * liquidity right now (in cooldown, reserved for LP withdrawals, ...).
 * @param {bigint} liquidityAssets withdrawable liquidity asset (getReserves)
 * @param {bigint} totalAssets ARM total assets
 * @returns {number} 0..10000; 10000 when totalAssets is 0, 0 when liquidity >= total
 */
const computeUtilisationBps = (liquidityAssets, totalAssets) => {
  if (totalAssets <= 0n) return Number(UTILISATION_SCALE);
  if (liquidityAssets >= totalAssets) return 0;
  const availableBps = (liquidityAssets * UTILISATION_SCALE) / totalAssets;
  return Number(UTILISATION_SCALE - availableBps);
};

/**
 * Tranche size S: a share of the available liquidity rounded to a step and
 * bounded to [minWei, liquidityAssets]. When less than minWei is available the
 * whole liquidity is the tranche.
 * @param {bigint} liquidityAssets available liquidity asset in wei
 * @param {number} pctBps share of liquidity, 3500 = 35%
 * @param {bigint} stepWei rounding step, eg 25,000e18
 * @param {bigint} minWei minimum tranche, eg 25,000e18
 * @example 200k liquidity, 35%, step 25k -> 75k; 20k liquidity -> 20k
 */
const computeTranche = ({ liquidityAssets, pctBps, stepWei, minWei }) => {
  if (stepWei <= 0n) throw new Error("Tranche step must be > 0");
  if (pctBps <= 0 || pctBps > Number(UTILISATION_SCALE)) {
    throw new Error(
      `Invalid tranche percentage ${pctBps}: must be 1..10000 bps`,
    );
  }
  if (liquidityAssets <= minWei) return liquidityAssets;

  const raw = (liquidityAssets * BigInt(pctBps)) / UTILISATION_SCALE;
  let tranche = ((raw + stepWei / 2n) / stepWei) * stepWei;
  if (tranche < minWei) tranche = minWei;
  if (tranche > liquidityAssets) tranche = liquidityAssets;
  return tranche;
};

/**
 * Aggregator quote size: the tranche, floored so tiny tranches still get a
 * meaningful quote.
 */
const resolveQuoteAmount = (tranche, minWei) =>
  tranche < minWei ? minWei : tranche;

/**
 * Whether the on-chain buy cap should be re-sent: the tranche shrank below
 * what is still open on-chain, or more than `toleranceBps` of it was consumed.
 * @param {bigint} remaining on-chain buyLiquidityRemaining
 * @param {bigint} target computed tranche
 * @param {number} toleranceBps 2500 = refresh once 25% of the tranche is used
 */
const shouldRefreshBuyCap = ({ remaining, target, toleranceBps }) => {
  if (remaining > target) return true;
  const floor = target - (target * BigInt(toleranceBps)) / UTILISATION_SCALE;
  return remaining < floor;
};

module.exports = {
  computeTranche,
  computeUtilisationBps,
  ladderDiscountBps100,
  ladderMaxBuyPrice,
  parseLadder,
  resolveQuoteAmount,
  scaledInt,
  shouldRefreshBuyCap,
};
