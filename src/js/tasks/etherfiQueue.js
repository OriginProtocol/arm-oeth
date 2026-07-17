const { gql } = require("@apollo/client/core");
const { Contract, parseUnits } = require("ethers");

const { baseWithdrawAmount } = require("./liquidityAutomation");
const {
  adapterContract,
  claimBaseAssetWithdrawal,
  requestBaseAssetWithdrawal,
  resolveArmBase,
} = require("../utils/arm");
const addresses = require("../utils/addresses");
const { createApolloClient } = require("../utils/apollo");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:etherfiQueue");

const uri = "https://origin.squids.live/ops-squid/graphql";

const ETHERFI_WITHDRAWAL_NFT_ABI = [
  "function isFinalized(uint256 requestId) view returns (bool)",
  "function getRequest(uint256 requestId) view returns (tuple(uint96 amountOfEEth, uint96 shareOfEEth, bool isValid, uint32 feeGwei))",
];

const requestEtherFiWithdrawals = async (options) => {
  const { signer, amount } = options;
  const baseContext = await resolveArmBase(options);
  const { baseSymbol } = baseContext;

  const withdrawAmount = amount
    ? parseUnits(amount.toString())
    : await baseWithdrawAmount(options);
  if (!withdrawAmount || withdrawAmount === 0n) return;

  log(`Requesting withdrawal for ${withdrawAmount} ${baseSymbol}...`);
  const tx = await requestBaseAssetWithdrawal({
    baseContext,
    signer,
    amount: withdrawAmount,
  });

  await logTxDetails(tx, "requestEtherFiWithdrawal");
};

const claimEtherFiWithdrawals = async (options) => {
  const { signer, id } = options;
  const baseContext = await resolveArmBase(options);

  const requestIds = id
    ? // If an id is provided, just claim that one
      [id]
    : // Get the outstanding EtherFi withdrawal requests for the ARM
      await claimableEtherFiRequests(signer);

  if (baseContext.version === "legacy") {
    if (requestIds.length > 0) {
      log(
        `About to claim ${requestIds.length} withdrawal requests with\nids: ${requestIds}`,
      );
      const tx = await claimBaseAssetWithdrawal({
        baseContext,
        signer,
        requestIds,
      });
      await logTxDetails(tx, "claim EtherFi withdraws");
    } else {
      log("No EtherFi withdrawal requests to claim");
    }
    return;
  }

  const adapter = await adapterContract(baseContext.config.adapter, signer);
  let shares = 0n;
  for (const requestId of requestIds) {
    shares += await adapter["requestShares(uint256)"](requestId);
  }

  if (shares === 0n) {
    log("No EtherFi withdrawal requests to claim");
    return;
  }

  log(
    `About to claim ${requestIds.length} withdrawal requests with\nids: ${requestIds}`,
  );
  const tx = await claimBaseAssetWithdrawal({
    baseContext,
    signer,
    shares,
  });
  await logTxDetails(tx, "claim EtherFi withdraws");
};

// Read the on-chain finalized/valid state of each subgraph-reported request.
// EtherFi never reverts on these views (isFinalized is a numeric comparison and
// getRequest returns a zeroed struct for burnt/unknown ids), so one stale id
// can't break the batch.
const etherFiRequestStatuses = async (withdrawalNFT, requestIds) =>
  Promise.all(
    requestIds.map(async (requestId) => {
      const [isFinalized, request] = await Promise.all([
        withdrawalNFT.isFinalized(requestId),
        withdrawalNFT.getRequest(requestId),
      ]);
      return { requestId, isFinalized, isValid: request.isValid };
    }),
  );

// Only finalized requests whose withdrawal NFT still exists (isValid) can be
// claimed. EtherFi's isFinalized() stays true after a claim and the ops-squid
// subgraph can lag on its `claimed` flag, so without this on-chain gate an
// already-claimed request keeps coming back and claimEtherFiWithdrawals reverts
// with "ERC721: invalid token ID" (the burnt NFT), wedging the action.
const selectClaimableEtherFiRequests = (statuses) =>
  statuses
    .filter(({ isFinalized, isValid }) => isFinalized && isValid)
    .map(({ requestId }) => requestId);

const claimableEtherFiRequests = async (signer) => {
  const client = createApolloClient(uri);

  log(`About to get claimable EtherFi withdrawal requests`);

  const query = gql`
    query ClaimableEtherFiRequestsQuery {
      etherfiWithdrawalRequests(
        where: { claimable_isNull: false, claimed_isNull: true }
        limit: 100
      ) {
        requestId
      }
    }
  `;

  let candidateIds;
  try {
    const { data } = await client.query({
      query,
    });
    candidateIds = data.etherfiWithdrawalRequests.map(
      (request) => request.requestId,
    );
  } catch (error) {
    const msg = `Failed to get claimable EtherFi withdrawal requests`;
    console.error(msg);
    throw Error(msg, { cause: error });
  }

  const withdrawalNFT = new Contract(
    addresses.mainnet.etherfiWithdrawalQueue,
    ETHERFI_WITHDRAWAL_NFT_ABI,
    signer,
  );
  const statuses = await etherFiRequestStatuses(withdrawalNFT, candidateIds);
  const claimableRequests = selectClaimableEtherFiRequests(statuses);

  const skipped = statuses
    .filter(({ isFinalized, isValid }) => !(isFinalized && isValid))
    .map(({ requestId }) => requestId);
  if (skipped.length > 0) {
    log(
      `Skipping ${skipped.length} subgraph requests not claimable on-chain (already claimed or not finalized): ${skipped}`,
    );
  }

  log(
    `Found ${claimableRequests.length} claimable withdrawal requests: ${claimableRequests}`,
  );

  return claimableRequests;
};

module.exports = {
  requestEtherFiWithdrawals,
  claimEtherFiWithdrawals,
  etherFiRequestStatuses,
  selectClaimableEtherFiRequests,
};
