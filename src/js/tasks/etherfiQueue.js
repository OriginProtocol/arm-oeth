const { ApolloClient, InMemoryCache, gql } = require("@apollo/client/core");
const { ethers, formatUnits, parseUnits } = require("ethers");

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
    // Check if there is WETH available in the lending market
    const activeMarketAddress = await arm.activeMarket();
    let marketHasWeth = false;

    if (activeMarketAddress !== ethers.ZeroAddress) {
      const activeMarket = new ethers.Contract(
        activeMarketAddress,
        ["function maxWithdraw(address) external view returns (uint256)"],
        signer,
      );
      const availableAssets = await activeMarket.maxWithdraw(
        await arm.getAddress(),
      );
      log(`${formatUnits(availableAssets)} WETH available in lending market`);
      marketHasWeth = availableAssets > 0n;
    }

    if (marketHasWeth) {
      // WETH still available in the lending market, skip small eETH withdrawal
      console.log(
        `withdraw amount of ${formatUnits(
          withdrawAmount,
        )} eETH is below ${minAmount} and lending market still has WETH, so not withdrawing`,
      );
      return;
    }

    if (withdrawAmount === 0n) {
      console.log(`No eETH left in the ARM to withdraw`);
      return;
    }

    // No WETH left in lending market, withdraw whatever eETH remains
    log(
      `No WETH in lending market, withdrawing remaining ${formatUnits(withdrawAmount)} eETH`,
    );
  }

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
