const { ApolloClient, InMemoryCache, gql } = require("@apollo/client/core");
const { parseUnits } = require("ethers");

const { baseWithdrawAmount } = require("./liquidityAutomation");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:etherfiQueue");

const uri = "https://origin.squids.live/ops-squid/graphql";

const requestEtherFiWithdrawals = async (options) => {
  const { signer, arm, amount } = options;

  const withdrawAmount = amount
    ? parseUnits(amount.toString())
    : await baseWithdrawAmount(options);
  if (!withdrawAmount || withdrawAmount === 0n) return;

  const tx = await arm.connect(signer).requestEtherFiWithdrawal(withdrawAmount);

  await logTxDetails(tx, "requestEtherFiWithdrawal");
};

const claimEtherFiWithdrawals = async (options) => {
  const { arm, signer, id } = options;

  const requestIds = id
    ? // If an id is provided, just claim that one
      [id]
    : // Get the outstanding EtherFi withdrawal requests for the ARM
      await claimableEtherFiRequests();

  if (requestIds.length > 0) {
    log(
      `About to claim ${requestIds.length} withdrawal requests with\nids: ${requestIds}`,
    );
    const tx = await arm.connect(signer).claimEtherFiWithdrawals(requestIds);
    await logTxDetails(tx, "claim EtherFi withdraws");
  } else {
    log("No EtherFi withdrawal requests to claim");
  }
};

const claimableEtherFiRequests = async () => {
  const client = new ApolloClient({
    uri,
    cache: new InMemoryCache(),
  });

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
