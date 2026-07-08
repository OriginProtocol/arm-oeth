const { encodeBytes32String, formatUnits, parseUnits } = require("ethers");
const { ethers } = require("ethers");

const { baseWithdrawAmount } = require("./liquidityAutomation");
const {
  claimBaseAssetWithdrawal,
  requestBaseAssetWithdrawal,
  resolveArmBase,
} = require("../utils/arm");
const { logTxDetails } = require("../utils/txLogger");
const log = require("../utils/logger")("task:paxosQueue");

const PAXOS_ADAPTER_ABI = [
  "function pendingShares() view returns (uint256)",
  "function settlingShares() view returns (uint256)",
  "function paxosRecipient() view returns (address)",
  "function submitPaxosRedeem(uint256 shares, bytes32 paxosRedemptionId)",
];

// Placeholder recipient the adapters were initialized with by deploy
// script 037. Submitting to it would burn the base assets.
const PLACEHOLDER_PAXOS_RECIPIENT =
  "0x000000000000000000000000000000000000dead";

const paxosAdapterContract = (adapterAddress, signer) =>
  new ethers.Contract(adapterAddress, PAXOS_ADAPTER_ABI, signer);

// Off-chain generated reconciliation tag, indexed in the adapter's
// PaxosRedeemSubmitted event. eg "PYUSD-1783421435"
const newPaxosRedemptionId = (baseSymbol) =>
  encodeBytes32String(`${baseSymbol}-${Math.floor(Date.now() / 1000)}`);

// Steps 1 and 2 of the Paxos redemption flow:
// 1. requestBaseAssetRedeem pulls the base asset from the ARM into the adapter
// 2. submitPaxosRedeem sends all pending shares to the Paxos redemption address
// Paxos then settles the liquidity asset 1:1 to the adapter off-chain.
const requestPaxosWithdrawals = async (options) => {
  const { signer, amount } = options;
  const baseContext = await resolveArmBase(options);
  const { baseSymbol, config } = baseContext;
  const decimals = Number(config.baseAssetDecimals ?? 6);

  // 1. Determine withdrawal amount: explicit input or calculate from ARM and lending market balances
  const withdrawAmount = amount
    ? parseUnits(amount.toString(), decimals)
    : await baseWithdrawAmount({ ...options, decimals });
  if (withdrawAmount && withdrawAmount !== 0n) {
    log(
      `Requesting redeem of ${formatUnits(withdrawAmount, decimals)} ${baseSymbol}`,
    );
    const tx = await requestBaseAssetWithdrawal({
      baseContext,
      signer,
      amount: withdrawAmount,
    });
    await logTxDetails(tx, "requestBaseAssetRedeem");
  }

  // 2. Submit all pending shares to Paxos. This also flushes shares left
  // pending by an earlier failed submit.
  const adapter = paxosAdapterContract(config.adapter, signer);
  const pendingShares = await adapter.pendingShares();
  if (pendingShares === 0n) {
    log(`No pending ${baseSymbol} shares to submit to Paxos`);
    return;
  }

  const recipient = await adapter.paxosRecipient();
  if (recipient.toLowerCase() === PLACEHOLDER_PAXOS_RECIPIENT) {
    throw new Error(
      `${baseSymbol} adapter paxosRecipient is still the placeholder address, refusing to submit to Paxos`,
    );
  }

  const paxosRedemptionId = newPaxosRedemptionId(baseSymbol);
  log(
    `Submitting ${formatUnits(pendingShares, decimals)} ${baseSymbol} to Paxos with redemption id ${paxosRedemptionId}`,
  );
  const tx = await adapter.submitPaxosRedeem(pendingShares, paxosRedemptionId);
  await logTxDetails(tx, "submitPaxosRedeem");
};

// Step 3 of the Paxos redemption flow: once Paxos has settled the liquidity
// asset to the adapter, pull it back into the ARM. Partial settlements are
// claimed incrementally.
const claimPaxosWithdrawals = async (options) => {
  const { signer, minAmount = 100 } = options;
  const baseContext = await resolveArmBase(options);
  const { baseSymbol, config, liquidityAddress } = baseContext;
  const decimals = Number(config.baseAssetDecimals ?? 6);

  const adapter = paxosAdapterContract(config.adapter, signer);
  const liquidityAsset = new ethers.Contract(
    liquidityAddress,
    ["function balanceOf(address) external view returns (uint256)"],
    signer,
  );
  const [settlingShares, settledBalance] = await Promise.all([
    adapter.settlingShares(),
    liquidityAsset.balanceOf(config.adapter),
  ]);

  const claimable =
    settlingShares < settledBalance ? settlingShares : settledBalance;
  const minAmountBI = parseUnits(minAmount.toString(), decimals);
  if (claimable === 0n || claimable < minAmountBI) {
    log(
      `Only ${formatUnits(claimable, decimals)} claimable for ${baseSymbol} (${formatUnits(settlingShares, decimals)} settling, ${formatUnits(settledBalance, decimals)} settled), skipping claim`,
    );
    return;
  }

  log(
    `Claiming ${formatUnits(claimable, decimals)} settled liquidity for ${baseSymbol}`,
  );
  const tx = await claimBaseAssetWithdrawal({
    baseContext,
    signer,
    shares: claimable,
  });
  await logTxDetails(tx, "claimBaseAssetRedeem");
};

module.exports = {
  requestPaxosWithdrawals,
  claimPaxosWithdrawals,
};
