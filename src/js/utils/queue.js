const { ApolloClient, InMemoryCache, gql } = require("@apollo/client/core");

const log = require("../utils/logger")("task:queue");

const uri = "https://origin.squids.live/origin-squid/graphql";

const outstandingWithdrawalAmount = async ({ withdrawer }) => {
  const client = new ApolloClient({
    uri,
    cache: new InMemoryCache(),
  });

  log(`About to get outstanding withdrawal requests for ${withdrawer}`);

  const query = gql`
    query OutstandingRequestsQuery($withdrawer: String!) {
      oethWithdrawalRequests(
        where: { withdrawer: $withdrawer, claimed_eq: false }
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
      variables: { withdrawer },
    });

    log(data);
    2;

    log(
      `Found ${data.oethWithdrawalRequests.length} outstanding withdrawal requests`
    );

    const amount = data.oethWithdrawalRequests.reduce(
      (acc, request) => acc + BigInt(request.amount),
      0n
    );

    return amount;
  } catch (error) {
    const msg = `Failed to get outstanding OETH withdrawals for ${withdrawer}`;
    console.error(msg);
    throw Error(msg, { cause: error });
  }
};

module.exports = { outstandingWithdrawalAmount };
