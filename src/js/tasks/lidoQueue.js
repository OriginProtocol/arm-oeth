const { ethers, formatUnits, parseUnits } = require("ethers");
const { baseWithdrawAmount } = require("./liquidityAutomation");
const { mainnet } = require("../utils/addresses");

const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:lidoQueue");

const lidoAsyncRedeemAdapterAbi = [
  "function requestWithdrawal(uint256 shares) returns (uint256 requestId)",
  "function claimWithdrawal(uint256[] requestIds, uint256[] hintIds) returns (uint256 assetsOut, uint256 sharesClaimed)",
];

const getAdapterAddress = async (arm, asset) => {
  const config = await arm.baseAssetConfigs(asset);
  return config.adapter ?? config[1];
};

const requestLidoWithdrawals = async (options) => {
  const { amount, signer, arm, maxAmount } = options;
  const adapterAddress = await getAdapterAddress(arm, mainnet.stETH);
  const adapter = new ethers.Contract(
    adapterAddress,
    lidoAsyncRedeemAdapterAbi,
    signer,
  );

  // Get stETH withdrawal amount
  const withdrawAmount = amount
    ? parseUnits(amount.toString())
    : await baseWithdrawAmount(options);
  if (!withdrawAmount || withdrawAmount === 0n) return;

  const maxAmountBI = parseUnits(maxAmount.toString());
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

  const txs = [];
  for (const requestAmount of requestAmounts) {
    txs.push(await adapter.requestWithdrawal(requestAmount));
  }

  for (const tx of txs) {
    await logTxDetails(tx, "requestLidoWithdrawals");
  }
};

const claimLidoWithdrawals = async (options) => {
  const { signer, arm, withdrawalQueue, id } = options;
  const adapterAddress = await getAdapterAddress(arm, mainnet.stETH);
  const adapter = new ethers.Contract(
    adapterAddress,
    lidoAsyncRedeemAdapterAbi,
    signer,
  );

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
    const tx = await adapter.claimWithdrawal(sortedFinalizedIds, hintIds.toArray());
    await logTxDetails(tx, "claim Lido withdraws");
  } else {
    log("No finalized Lido withdrawal requests to claim");
  }
};

module.exports = {
  requestLidoWithdrawals,
  claimLidoWithdrawals,
};
