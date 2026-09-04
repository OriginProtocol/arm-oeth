import { ethers } from "ethers";
import { types } from "hardhat/config";

import { action } from "../lib/action";
import { setPrices } from "../armPrices";
import { setPricesForBases } from "../../utils/priceActionUtils";
import { mainnet } from "../../utils/addresses";
import { resolveEthenaTranche } from "../../utils/ethenaPricing";
import { scaledInt } from "../../utils/tranchePricing";
const ethenaARMAbi = require("../../../abis/EthenaARM.json");

const DEFAULT_LADDER = "50:2.5,70:3.5,85:5";

action({
  name: "setPricesEthena",
  description: "Set prices for Ethena ARM",
  chains: [1],
  // Price points are operator-overridable from the scheduled command in
  // talos (talos UI → schedules → command field). Defaults match what
  // was hardcoded previously so existing seed commands without overrides
  // keep their old behavior.
  params: (t) =>
    t
      .addOptionalParam(
        "buyPrice",
        "Exact buy price; when set, sellPrice must also be set (USDe per sUSDe).",
        undefined,
        types.float,
      )
      .addOptionalParam(
        "sellPrice",
        "Exact sell price; when set, buyPrice must also be set (sUSDe per USDe).",
        undefined,
        types.float,
      )
      .addOptionalParam(
        "buyAmount",
        "USDe remaining at the buy price, in token units (1 = 1 USDe).",
        undefined,
        types.float,
      )
      .addOptionalParam(
        "sellAmount",
        "sUSDe remaining at the sell price, in token units (1 = 1 sUSDe).",
        undefined,
        types.float,
      )
      .addOptionalParam(
        "maxBuyPrice",
        "Upper bound for buy-side price (USDe per sUSDe).",
        0.99985,
        types.float,
      )
      .addOptionalParam(
        "minBuyPrice",
        "Lower bound for buy-side price (USDe per sUSDe).",
        0.998,
        types.float,
      )
      .addOptionalParam(
        "maxSellPrice",
        "Upper bound for sell-side price (sUSDe per USDe).",
        0.99999,
        types.float,
      )
      .addOptionalParam(
        "minSellPrice",
        "Lower bound for sell-side price (sUSDe per USDe).",
        0.99996,
        types.float,
      )
      .addOptionalParam(
        "amount",
        "Override for the DEX swap amount used to fetch the reference price quote.",
        undefined,
        types.float,
      )
      .addOptionalParam(
        "inch",
        "Use 1Inch as the aggregator price source.",
        false,
        types.boolean,
      )
      .addOptionalParam(
        "kyber",
        "Use Kyber as the aggregator price source.",
        true,
        types.boolean,
      )
      .addOptionalParam(
        "offset",
        "Price offset applied to aggregator quotes.",
        0.2,
        types.float,
      )
      .addOptionalParam(
        "dynamicOffset",
        "Use a dynamic offset that scales from zero at cross price to the DEX spread at the full-spread price.",
        false,
        types.boolean,
      )
      .addOptionalParam(
        "dynamicOffsetFullSpreadPrice",
        "DEX sell price where dynamic offset reaches 100% of the DEX spread.",
        0.999,
        types.float,
      )
      .addOptionalParam(
        "tolerance",
        "Tolerance used when comparing target and current prices.",
        0.09,
        types.float,
      )
      .addOptionalParam(
        "fee",
        "Swap fee in basis points used by setPrices when computing target prices.",
        2,
        types.float,
      )
      .addOptionalParam(
        "tranche",
        "Tranche pricing: the buy liquidity limit and the aggregator quote size are one tranche of the available liquidity, and the max buy price follows the utilisation ladder. Overrides --buy-amount, --amount and tightens --max-buy-price.",
        false,
        types.boolean,
      )
      .addOptionalParam(
        "tranchePct",
        "Tranche as a percentage of the available liquidity (35 = 35%).",
        35,
        types.float,
      )
      .addOptionalParam(
        "trancheStep",
        "Rounding step of the tranche in USDe (25000 = round to 25k).",
        25000,
        types.float,
      )
      .addOptionalParam(
        "trancheMin",
        "Minimum tranche in USDe; below it the whole liquidity is the tranche.",
        25000,
        types.float,
      )
      .addOptionalParam(
        "ladder",
        "Utilisation ladder as 'u%:bps,...': minimum discount below NAV in basis points at each utilisation level, linearly interpolated (50:2.5,70:3.5,85:5 = 2.5 bps below 50% deployed, 3.5 bps at 70%, 5 bps from 85%).",
        DEFAULT_LADDER,
        types.string,
      )
      .addOptionalParam(
        "ladderStep",
        "Quantisation of the ladder discount in basis points (0.25 = the max buy price moves in 0.25 bps notches).",
        0.25,
        types.float,
      )
      .addOptionalParam(
        "capTolerance",
        "Share of the tranche that must be consumed before the buy limit alone triggers an update (0.25 = 25%).",
        0.25,
        types.float,
      )
      .addOptionalParam(
        "dryrun",
        "Compute and log the target prices without sending the transaction.",
        false,
        types.boolean,
      ),
  run: async ({ signer, log, args }) => {
    const arm = new ethers.Contract(mainnet.ethenaARM, ethenaARMAbi, signer);
    // Pin the block so the tranche, the utilisation and the on-chain limits
    // compared in setPrices all come from the same state.
    const blockTag = await signer.provider!.getBlockNumber();

    log.info("Setting prices for Ethena ARM");

    const trancheParams = args.tranche
      ? {
          tranchePctBps: scaledInt(args.tranchePct, 100, "tranche percentage"),
          trancheStepWei: ethers.parseUnits(args.trancheStep.toString(), 18),
          trancheMinWei: ethers.parseUnits(args.trancheMin.toString(), 18),
          ladder: args.ladder,
          ladderStepBps100: scaledInt(args.ladderStep, 100, "ladder step"),
          buyCapToleranceBps: scaledInt(args.capTolerance, 10000, "cap tolerance"),
        }
      : undefined;

    if (trancheParams) {
      if (args.buyAmount !== undefined || args.amount !== undefined) {
        log.warn(
          "--tranche is set: --buy-amount and --amount are ignored, the tranche sets both",
        );
      }
      log.info(
        `Tranche pricing: ${args.tranchePct}% of liquidity (step ${args.trancheStep}, min ${args.trancheMin}), ladder ${args.ladder} quantised to ${args.ladderStep} bps, cap tolerance ${args.capTolerance}`,
      );
    }

    const setPricesFn = trancheParams
      ? async (options: any) => {
          const overrides = await resolveEthenaTranche({
            arm,
            armName: options.armName,
            base: options.base,
            blockTag,
            maxBuyPrice: options.maxBuyPrice,
            ...trancheParams,
          });
          return setPrices({
            ...options,
            buyAmount: overrides.buyAmount,
            amount: overrides.amount,
            maxBuyPrice: overrides.maxBuyPrice,
          });
        }
      : setPrices;

    await setPricesForBases({
      setPrices: setPricesFn,
      bases: ["SUSDE"],
      options: {
        signer,
        arm,
        armName: "Ethena",
        buyPrice: args.buyPrice,
        sellPrice: args.sellPrice,
        buyAmount: args.buyAmount,
        sellAmount: args.sellAmount,
        maxSellPrice: args.maxSellPrice,
        minSellPrice: args.minSellPrice,
        maxBuyPrice: args.maxBuyPrice,
        minBuyPrice: args.minBuyPrice,
        kyber: args.kyber,
        inch: args.inch,
        amount: args.amount,
        tolerance: args.tolerance,
        fee: args.fee,
        offset: args.offset,
        dynamicOffset: args.dynamicOffset,
        dynamicOffsetFullSpreadPrice: args.dynamicOffsetFullSpreadPrice,
        priceOffset: true,
        blockTag,
        wrapped: true,
        dryrun: args.dryrun,
        buyCapToleranceBps: trancheParams?.buyCapToleranceBps,
      },
    });
  },
});
