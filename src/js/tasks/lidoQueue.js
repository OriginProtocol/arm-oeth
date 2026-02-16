const { ethers, formatUnits, parseUnits } = require("ethers");

const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:lidoQueue");

const requestLidoWithdrawals = async (options) => {
  const { signer, steth, arm, amount, minAmount, maxAmount } = options;

  const withdrawAmount = amount
    ? parseUnits(amount.toString())
    : await steth.balanceOf(arm.getAddress());
  log(`${formatUnits(withdrawAmount)} stETH withdraw amount`);

  const minAmountBI = parseUnits(minAmount.toString());
  const maxAmountBI = parseUnits(maxAmount.toString());

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
      // WETH still available in the lending market, skip small stETH withdrawal
      console.log(
        `withdraw amount of ${formatUnits(
          withdrawAmount,
        )} stETH is below ${minAmount} and lending market still has WETH, so not withdrawing`,
      );
      return;
    }

    if (withdrawAmount === 0n) {
      console.log(`No stETH left in the ARM to withdraw`);
      return;
    }

    // No WETH left in lending market, withdraw whatever stETH remains
    log(
      `No WETH in lending market, withdrawing remaining ${formatUnits(withdrawAmount)} stETH`,
    );
  }

  const requestAmounts = [];
  let remainingAmount = withdrawAmount;
  while (remainingAmount > 0) {
    const requestAmount =
      remainingAmount > maxAmountBI ? maxAmountBI : remainingAmount;
    requestAmounts.push(requestAmount);
    remainingAmount -= requestAmount;
    log(
      `About to request ${formatUnits(
        requestAmount,
      )} stETH withdrawal from Lido`,
    );
  }

  const tx = await arm.connect(signer).requestLidoWithdrawals(requestAmounts);

  await logTxDetails(tx, "requestLidoWithdrawals");
};

const claimLidoWithdrawals = async (options) => {
  const { signer, arm, withdrawalQueue, id } = options;

  const finalizedIds = [];

  if (id) {
    finalizedIds.push(id);
  } else {
    // Get the outstanding Lido withdrawal requests for the ARM
    const requestIds = await withdrawalQueue.getWithdrawalRequests(
      arm.getAddress(),
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
        `Withdrawal request ${id} finalized ${status.isFinalized}, claimed ${status.isClaimed}`,
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

    const lastIndex = await withdrawalQueue.getLastCheckpointIndex();
    const hintIds = await withdrawalQueue.findCheckpointHints(
      sortedFinalizedIds,
      "1",
      lastIndex,
    );

    log(
      `About to claim ${sortedFinalizedIds.length} withdrawal requests with\nids: ${sortedFinalizedIds}\nhints: ${hintIds}`,
    );
    const tx = await arm
      .connect(signer)
      .claimLidoWithdrawals(sortedFinalizedIds, hintIds.toArray());
    await logTxDetails(tx, "claim Lido withdraws");
  } else {
    log("No finalized Lido withdrawal requests to claim");
  }
};

module.exports = {
  requestLidoWithdrawals,
  claimLidoWithdrawals,
};
