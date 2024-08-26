const { ApolloClient, InMemoryCache, gql } = require("@apollo/client/core");
const dayjs = require("dayjs");
const utc = require("dayjs/plugin/utc");
const { formatUnits } = require("ethers");

// Extend Day.js with the UTC plugin
dayjs.extend(utc);

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
        where: { withdrawer_eq: $withdrawer, claimed_eq: false }
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

const claimableRequests = async ({ withdrawer, queuedAmountClaimable }) => {
  const client = new ApolloClient({
    uri,
    cache: new InMemoryCache(),
  });

  log(
    `About to get claimable withdrawal requests for withdrawer ${withdrawer} up to ${formatUnits(
      queuedAmountClaimable
    )} WETH`
  );

  const query = gql`
    query ClaimableRequestsQuery(
      $withdrawer: String!
      $liquidity: BigInt!
      $tenMinutesAgo: DateTime!
    ) {
      oethWithdrawalRequests(
        where: {
          withdrawer_eq: $withdrawer
          claimed_eq: false
          queued_lte: $liquidity
          timestamp_lt: $tenMinutesAgo
        }
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
    // Get the Date time of 10 minutes ago
    const now = dayjs();
    const tenMinutesAgo = now.subtract(10, "minute");

    log(`Ten minutes ago: ${tenMinutesAgo}`);

    const { data } = await client.query({
      query,
      variables: {
        withdrawer: withdrawer.toLowerCase(),
        liquidity: queuedAmountClaimable.toString(),
        tenMinutesAgo,
      },
    });

    log(
      `Found ${data.oethWithdrawalRequests.length} claimable withdrawal requests`
    );

    return data.oethWithdrawalRequests.map((request) => request.requestId);
  } catch (error) {
    const msg = `Failed to get claimable OETH withdrawals for ${withdrawer}`;
    console.error(msg);
    throw Error(msg, { cause: error });
  }
};

module.exports = { claimableRequests, outstandingWithdrawalAmount };
