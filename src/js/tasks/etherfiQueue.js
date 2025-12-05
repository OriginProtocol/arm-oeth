const { ApolloClient, InMemoryCache, gql } = require("@apollo/client/core");
const { formatUnits, parseUnits } = require("ethers");

const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:etherfiQueue");

const uri = "https://origin.squids.live/ops-squid/graphql";

const requestEtherFiWithdrawals = async (options) => {
  const { signer, eeth, arm, amount, minAmount } = options;

  const withdrawAmount = amount
    ? parseUnits(amount.toString())
    : await eeth.balanceOf(arm.getAddress());
  log(`${formatUnits(withdrawAmount)} eETH withdraw amount`);

  const minAmountBI = parseUnits(minAmount.toString());

  if (!amount && withdrawAmount <= minAmountBI) {
    console.log(
      `withdraw amount of ${formatUnits(
        withdrawAmount,
      )} eETH is below ${minAmount} so not withdrawing`,
    );
    return;
  }

  const tx = await arm.connect(signer).requestEtherFiWithdrawal(withdrawAmount);

  await logTxDetails(tx, "requestEtherFiWithdrawal");
};

const claimEtherFiWithdrawals = async (options) => {
  const { arm, signer, id } = options;

  const requestIds = id
    ? // If an id is provided, just claim that one
      requestIds.push(id)
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
