const { gql } = require("@apollo/client/core");
const { parseUnits } = require("ethers");

const { baseWithdrawAmount } = require("./liquidityAutomation");
const { adapterContract, resolveArmBase } = require("../utils/arm");
const { createApolloClient } = require("../utils/apollo");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:etherfiQueue");

const uri = "https://origin.squids.live/ops-squid/graphql";

const requestEtherFiWithdrawals = async (options) => {
  const { signer, arm, amount } = options;
  const { baseSymbol, baseAddress } = await resolveArmBase(options);

  const withdrawAmount = amount
    ? parseUnits(amount.toString())
    : await baseWithdrawAmount(options);
  if (!withdrawAmount || withdrawAmount === 0n) return;

  log(`Requesting withdrawal for ${withdrawAmount} ${baseSymbol}...`);
  const tx = await arm
    .connect(signer)
    .requestRedeem(baseAddress, withdrawAmount);

  await logTxDetails(tx, "requestEtherFiWithdrawal");
};

const claimEtherFiWithdrawals = async (options) => {
  const { arm, signer, id } = options;
  const { baseAddress, config } = await resolveArmBase(options);
  const adapter = await adapterContract(config.adapter, signer);

  const requestIds = id
    ? // If an id is provided, just claim that one
      [id]
    : // Get the outstanding EtherFi withdrawal requests for the ARM
      await claimableEtherFiRequests();

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
  const tx = await arm.connect(signer).claimRedeem(baseAddress, shares);
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
