const { ApolloClient, InMemoryCache, gql } = require("@apollo/client/core");

const log = require("./logger")("utils:os:staking");

const uri = "https://origin.squids.live/origin-squid/graphql";

const outstandingValidatorWithdrawalRequests = async () => {
  const client = new ApolloClient({
    uri,
    cache: new InMemoryCache(),
  });

  log(`About to get outstanding undelegate requests from the Sonic validators`);

  const query = gql`
    query OutstandingUndelegateRequests {
      sfcWithdrawals(
        limit: 100
        orderBy: wrID_ASC
        where: { withdrawnAt_isNull: true, chainId_eq: 146 }
      ) {
        id
        amount
        wrID
        toValidatorID
        createdAt
      }
    }
  `;

  try {
    const { data } = await client.query({
      query,
    });

    log(`Found ${data.sfcWithdrawals.length} outstanding undelegate requests`);

    return data.sfcWithdrawals;
  } catch (error) {
    const msg = `Failed to get outstanding Sonic undelegate requests`;
    console.error(msg);
    throw Error(msg, { cause: error });
  }
};

module.exports = {
  outstandingValidatorWithdrawalRequests,
};
