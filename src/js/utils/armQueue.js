const { ApolloClient, InMemoryCache, gql } = require("@apollo/client/core");
const { formatUnits } = require("ethers");

const log = require("./logger")("utils:queue");

const uri = "https://origin.squids.live/origin-squid/graphql";

const outstandingWithdrawalAmount = async ({ withdrawer }) => {
  const client = new ApolloClient({
    uri,
    cache: new InMemoryCache(),
  });

  log(`About to get outstanding withdrawal requests for ${withdrawer}`);

  const query = gql`
    query OutstandingRequestsQuery($withdrawer: String!) {
      oTokenWithdrawalRequests(
        where: { withdrawer_eq: $withdrawer, claimed_eq: false }
        limit: 100
      ) {
        id
        amount
        queued
        claimed
        requestId
        timestamp
        txHash
      }
    }
  `;

  try {
    const { data } = await client.query({
      query,
      variables: { withdrawer: withdrawer.toLowerCase() },
    });

    log(
      `Found ${data.oTokenWithdrawalRequests.length} outstanding withdrawal requests`,
    );

    const amount = data.oTokenWithdrawalRequests.reduce(
      (acc, request) => acc + BigInt(request.amount),
      0n,
    );

    return amount;
  } catch (error) {
    const msg = `Failed to get outstanding OETH withdrawals for ${withdrawer}`;
    console.error(msg);
    throw Error(msg, { cause: error });
  }
};

const claimableRequests = async ({
  withdrawer,
  queuedAmountClaimable,
  claimCutoff,
}) => {
  const client = new ApolloClient({
    uri,
    cache: new InMemoryCache(),
  });

  log(
    `About to get claimable withdrawal requests for withdrawer ${withdrawer} up to ${formatUnits(
      queuedAmountClaimable,
    )}`,
  );

  const query = gql`
    query ClaimableRequestsQuery(
      $withdrawer: String!
      $liquidity: BigInt!
      $claimCutoff: DateTime!
    ) {
      oTokenWithdrawalRequests(
        where: {
          withdrawer_eq: $withdrawer
          claimed_eq: false
          queued_lte: $liquidity
          timestamp_lt: $claimCutoff
        }
        limit: 100
      ) {
        id
        amount
        queued
        claimed
        requestId
        timestamp
        txHash
      }
    }
  `;

  try {
    const { data } = await client.query({
      query,
      variables: {
        withdrawer: withdrawer.toLowerCase(),
        liquidity: queuedAmountClaimable.toString(),
        claimCutoff: claimCutoff.toISOString(),
      },
    });

    log(
      `Found ${data.oTokenWithdrawalRequests.length} claimable withdrawal requests`,
    );

    return data.oTokenWithdrawalRequests.map((request) => request.requestId);
  } catch (error) {
    const msg = `Failed to get claimable OETH withdrawals for ${withdrawer}`;
    console.error(msg);
    throw Error(msg, { cause: error });
  }
};

module.exports = { claimableRequests, outstandingWithdrawalAmount };
