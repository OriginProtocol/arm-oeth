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
const { parseRequestIds } = require("../utils/requestIds");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:etherfiQueue");

const uri = "https://origin.squids.live/ops-squid/graphql";
const MAX_EETH_WITHDRAW_AMOUNT = parseUnits("1000");

const ETHERFI_WITHDRAWAL_NFT_ABI = [
  "function isFinalized(uint256 requestId) view returns (bool)",
  "function getRequest(uint256 requestId) view returns (tuple(uint96 amountOfEEth, uint96 shareOfEEth, bool isValid, uint32 feeGwei))",
];

const splitEtherFiWithdrawAmount = (
  withdrawAmount,
  maxAmount = MAX_EETH_WITHDRAW_AMOUNT,
) => {
  if (maxAmount <= 0n) throw new Error("maxAmount must be greater than zero");

  const requestAmounts = [];
  let remainingAmount = withdrawAmount;
  while (remainingAmount > 0n) {
    const requestAmount =
      remainingAmount > maxAmount ? maxAmount : remainingAmount;
    requestAmounts.push(requestAmount);
    remainingAmount -= requestAmount;
  }
  return requestAmounts;
};

const maxEtherFiWithdrawShares = async (baseContext, signer) => {
  if (baseContext.version === "legacy" || baseContext.baseSymbol !== "WEETH") {
    return MAX_EETH_WITHDRAW_AMOUNT;
  }

  const adapter = await adapterContract(baseContext.config.adapter, signer);
  return adapter.convertToShares(MAX_EETH_WITHDRAW_AMOUNT);
};

const requestEtherFiWithdrawals = async (options) => {
  const { signer, amount } = options;
  const baseContext = await resolveArmBase(options);
  const { baseSymbol } = baseContext;

  const withdrawAmount = amount
    ? parseUnits(amount.toString())
    : await baseWithdrawAmount(options);
  if (!withdrawAmount || withdrawAmount === 0n) return;

  const maxWithdrawShares = await maxEtherFiWithdrawShares(baseContext, signer);
  const requestAmounts = splitEtherFiWithdrawAmount(
    withdrawAmount,
    maxWithdrawShares,
  );
  for (const requestAmount of requestAmounts) {
    log(`Requesting withdrawal for ${requestAmount} ${baseSymbol}...`);
    const tx = await requestBaseAssetWithdrawal({
      baseContext,
      signer,
      amount: requestAmount,
    });

    await logTxDetails(tx, "requestEtherFiWithdrawal");
  }
};

const claimEtherFiWithdrawals = async (options) => {
  const { signer } = options;
  const baseContext = await resolveArmBase(options);

  const selectedRequestIds = parseRequestIds(options);
  const requestIds = selectedRequestIds
    ? // If ids are provided, claim exactly those requests.
      selectedRequestIds
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

// Retry only the read-only subgraph lookup, never a claim transaction.
const queryEtherFiWithdrawalRequests = async (
  client,
  wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
) => {
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

  const maxAttempts = 3;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const { data } = await client.query({
        query,
        fetchPolicy: "network-only",
      });
      return data.etherfiWithdrawalRequests.map((request) => request.requestId);
    } catch (error) {
      const networkError = error.networkError;
      const statusCode = networkError?.statusCode;
      const details = [
        statusCode && `HTTP ${statusCode}`,
        error.message,
        networkError?.message,
        ...(error.graphQLErrors ?? []).map((item) => item.message),
        ...(networkError?.result?.errors ?? []).map((item) => item.message),
      ].filter(Boolean);
      const msg = `Failed to get claimable EtherFi withdrawal requests from ${uri} (attempt ${attempt}/${maxAttempts}): ${[...new Set(details)].join("; ")}`;
      const retryable =
        networkError &&
        (statusCode == null ||
          statusCode === 408 ||
          statusCode === 429 ||
          statusCode >= 500);
      if (!retryable || attempt === maxAttempts) {
        throw new Error(msg, { cause: error });
      }
      log(`${msg}. Retrying...`);
      await wait(1000 * 2 ** (attempt - 1));
    }
  }
};

const claimableEtherFiRequests = async (signer) => {
  const client = createApolloClient(uri);
  log(`About to get claimable EtherFi withdrawal requests`);
  const candidateIds = await queryEtherFiWithdrawalRequests(client);

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
  queryEtherFiWithdrawalRequests,
  etherFiRequestStatuses,
  selectClaimableEtherFiRequests,
  splitEtherFiWithdrawAmount,
};
