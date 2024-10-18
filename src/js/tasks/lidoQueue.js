const { formatUnits, parseUnits } = require("ethers");

const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:lidoQueue");

const requestLidoWithdrawals = async (options) => {
  const { signer, steth, arm, amount, minAmount } = options;

  const withdrawAmount = amount
    ? parseUnits(amount.toString())
    : await steth.balanceOf(arm.getAddress());
  log(`${formatUnits(withdrawAmount)} stETH withdraw amount`);

  const minAmountBI = parseUnits(minAmount.toString());

  if (!amount && withdrawAmount <= minAmountBI) {
    console.log(
      `withdraw amount of ${formatUnits(
        withdrawAmount
      )} stETH is below ${minAmount} so not withdrawing`
    );
    return;
  }

  log(
    `About to request ${formatUnits(withdrawAmount)} stETH withdrawal from Lido`
  );

  const tx = await arm.connect(signer).requestLidoWithdrawals([withdrawAmount]);

  await logTxDetails(tx, "requestLidoWithdrawals");
};

const claimLidoWithdrawals = async (options) => {
  const { signer, arm, withdrawalQueue, id } = options;

  const finalizedIds = [];

  if (id) {
    finalizedIds.push(id);
  } else {
    // Get the outstanding withdrawal requests for the AMM
    const requestIds = await withdrawalQueue.getWithdrawalRequests(
      arm.getAddress()
    );
    log(`Found ${requestIds.length} withdrawal requests`);

    if (requestIds.length === 0) {
      return;
    }

    const statuses = await withdrawalQueue.getWithdrawalStatus([...requestIds]);
    log(`Got ${statuses.length} statuses`);

    // For each AMM withdraw request
    for (const [index, status] of statuses.entries()) {
      const id = requestIds[index];
      log(
        `Withdrawal request ${id} finalized ${status.isFinalized}, claimed ${status.isClaimed}`
      );

      // If finalized but not yet claimed
      if (status.isFinalized && !status.isClaimed) {
        finalizedIds.push(id);
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
    log(`About to claim withdrawal request ids: ${sortedFinalizedIds}`);
    const tx = await arm
      .connect(signer)
      .claimLidoWithdrawals(sortedFinalizedIds);
    await logTxDetails(tx, "claim Lido withdraws");
  } else {
    log("No finalized Lido withdrawal requests to claim");
  }
};

async function collectFees({ arm, signer }) {
  log(`About to collect fees from the Lido ARM`);
  const tx = await arm.connect(signer).collectFees();
  await logTxDetails(tx, "collectFees");
}

module.exports = {
  collectFees,
  requestLidoWithdrawals,
  claimLidoWithdrawals,
};
