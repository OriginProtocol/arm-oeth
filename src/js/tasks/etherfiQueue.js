const { gql } = require("@apollo/client/core");
const { parseUnits } = require("ethers");

const { baseWithdrawAmount } = require("./liquidityAutomation");
const {
  adapterContract,
  claimBaseAssetWithdrawal,
  requestBaseAssetWithdrawal,
  resolveArmBase,
} = require("../utils/arm");
const { createApolloClient } = require("../utils/apollo");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:etherfiQueue");

const uri = "https://origin.squids.live/ops-squid/graphql";

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
      await claimableEtherFiRequests();

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

const claimableEtherFiRequests = async () => {
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

  try {
    const { data } = await client.query({
      query,
    });

    const claimableRequests = data.etherfiWithdrawalRequests.map(
      (request) => request.requestId,
    );

    log(
      `Found ${claimableRequests.length} claimable withdrawal requests: ${claimableRequests}`,
    );

    return claimableRequests;
  } catch (error) {
    const msg = `Failed to get claimable EtherFi withdrawal requests`;
    console.error(msg);
    throw Error(msg, { cause: error });
  }
};

module.exports = {
  requestEtherFiWithdrawals,
  claimEtherFiWithdrawals,
};
