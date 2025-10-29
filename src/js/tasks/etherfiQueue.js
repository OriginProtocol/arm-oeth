const { formatUnits, parseUnits } = require("ethers");

const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:etherfiQueue");

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
  const { signer, arm, withdrawalQueue, id } = options;

  const finalizedIds = [];

  if (id) {
    finalizedIds.push(id);
  } else {
    // Get the outstanding withdrawal requests for the AMM
    // This section doesn't work at the moment, because there is nothing that returns the request IDs owned by an address.
    const requestIds = await withdrawalQueue.getWithdrawalRequests(
      arm.getAddress(),
    );
    log(`Found ${requestIds.length} withdrawal requests`);

    if (requestIds.length === 0) {
      return;
    }

    // Get the last finalized request id from the WithdrawalQueue
    const lastFinalized = await withdrawalQueue.lastFinalizedRequestId();

    for (let i = 0; i < requestIds.length; i++) {
      const requestId = requestIds[i];

      // Check if the request is finalized
      // Returns (uint96 amountOfEEth, uint96 shareOfEEth, bool isValid, uint32 feeGwei)
      const [, , isValid] = await withdrawalQueue.getRequest(requestId);
      const isFinalized = requestId <= lastFinalized;

      if (isValid && isFinalized) {
        finalizedIds.push(requestId);
      }
    }
  }

  if (finalizedIds.length > 0) {
    // sort in ascending order
    const sortedFinalizedIds = finalizedIds.sort(function (a, b) {
      if (a > b) {
        return 1;
      } else if (a < b) {
        return -1;
      } else {
        return 0;
      }
    });

    log(
      `About to claim ${sortedFinalizedIds.length} withdrawal requests with\nids: ${sortedFinalizedIds}`,
    );
    const tx = await arm
      .connect(signer)
      .claimEtherFiWithdrawals(sortedFinalizedIds);
    await logTxDetails(tx, "claim EtherFi withdraws");
  } else {
    log("No finalized EtherFi withdrawal requests to claim");
  }
};

module.exports = {
  requestEtherFiWithdrawals,
  claimEtherFiWithdrawals,
};
