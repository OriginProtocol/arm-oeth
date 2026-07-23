const { formatUnits, parseUnits } = require("ethers");
const { baseWithdrawAmount } = require("./liquidityAutomation");

const {
  adapterContract,
  claimBaseAssetWithdrawal,
  requestBaseAssetWithdrawal,
  resolveArmBase,
} = require("../utils/arm");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:lidoQueue");

const requestLidoWithdrawals = async (options) => {
  const { amount, signer } = options;
  const baseContext = await resolveArmBase(options);
  const { baseSymbol } = baseContext;

  const withdrawAmount = amount
    ? parseUnits(amount.toString())
    : await baseWithdrawAmount(options);
  if (!withdrawAmount || withdrawAmount === 0n) return;

  if (baseContext.version === "legacy") {
    const maxAmountBI =
      options.maxAmount === undefined
        ? withdrawAmount
        : parseUnits(options.maxAmount.toString());
    if (maxAmountBI <= 0n) {
      throw new Error("maxAmount must be greater than zero");
    }
    let remainingAmount = withdrawAmount;
    while (remainingAmount > 0n) {
      const requestAmount =
        remainingAmount > maxAmountBI ? maxAmountBI : remainingAmount;
      log(
        `About to request ${formatUnits(
          requestAmount,
        )} ${baseSymbol} withdrawal from Lido`,
      );
      remainingAmount -= requestAmount;
    }
  } else {
    const maxAmountBI =
      options.maxAmount === undefined
        ? withdrawAmount
        : parseUnits(options.maxAmount.toString());
    if (maxAmountBI <= 0n) {
      throw new Error("maxAmount must be greater than zero");
    }
    let remainingAmount = withdrawAmount;
    while (remainingAmount > 0n) {
      const requestAmount =
        remainingAmount > maxAmountBI ? maxAmountBI : remainingAmount;
      log(
        `About to request ${formatUnits(
          requestAmount,
        )} ${baseSymbol} withdrawal from Lido`,
      );
      const tx = await requestBaseAssetWithdrawal({
        baseContext,
        signer,
        amount: requestAmount,
      });
      await logTxDetails(tx, "requestRedeem");
      remainingAmount -= requestAmount;
    }
    return;
  }

  log(
    `About to request ${formatUnits(withdrawAmount)} ${baseSymbol} withdrawal from Lido`,
  );

  const tx = await requestBaseAssetWithdrawal({
    baseContext,
    signer,
    amount: withdrawAmount,
    maxAmount: options.maxAmount,
  });

  await logTxDetails(tx, "requestRedeem");
};

const claimLidoWithdrawals = async (options) => {
  const { signer, id, withdrawalQueue } = options;
  const baseContext = await resolveArmBase(options);
  const { config } = baseContext;

  if (baseContext.version === "legacy") {
    if (!withdrawalQueue) {
      throw new Error("Legacy Lido claims require the Lido withdrawal queue");
    }

    const finalizedIds = [];
    if (id) {
      finalizedIds.push(id);
    } else {
      const requestIds = await withdrawalQueue.getWithdrawalRequests(
        await baseContext.arm.getAddress(),
      );
      log(`Found ${requestIds.length} withdrawal requests`);

      if (requestIds.length === 0) return;

      const statuses = await withdrawalQueue.getWithdrawalStatus([
        ...requestIds,
      ]);
      log(`Got ${statuses.length} statuses`);

      for (const [index, status] of statuses.entries()) {
        const requestId = requestIds[index];
        log(
          `Withdrawal request ${requestId} finalized ${status.isFinalized}, claimed ${status.isClaimed}`,
        );
        if (status.isFinalized && !status.isClaimed) {
          finalizedIds.push(requestId);
        }
      }
    }

    if (finalizedIds.length === 0) {
      log("No finalized Lido withdrawal requests to claim");
      return;
    }

    const sortedFinalizedIds = finalizedIds.sort((a, b) =>
      a > b ? 1 : a < b ? -1 : 0,
    );
    const lastIndex = await withdrawalQueue.getLastCheckpointIndex();
    const hintIds = await withdrawalQueue.findCheckpointHints(
      sortedFinalizedIds,
      "1",
      lastIndex,
    );

    log(
      `About to claim ${sortedFinalizedIds.length} withdrawal requests with\nids: ${sortedFinalizedIds}\nhints: ${hintIds}`,
    );
    const tx = await claimBaseAssetWithdrawal({
      baseContext,
      signer,
      requestIds: sortedFinalizedIds,
      hintIds: hintIds.toArray(),
    });
    await logTxDetails(tx, "claim Lido withdraws");
    return;
  }

  const adapter = await adapterContract(config.adapter, signer);

  let shares;
  if (id) {
    shares = await adapter["requestShares(uint256)"](id);
    if (shares === 0n) {
      log(
        `Withdrawal request ${id} does not belong to the ${baseContext.baseSymbol} adapter`,
      );
      return;
    }
  } else {
    try {
      [shares] = await adapter.claimableRedeem();
    } catch {
      shares = 0n;
    }
    if (shares === 0n) {
      log("No finalized Lido withdrawal requests to claim");
      return;
    }
  }

  log(`About to claim ${formatUnits(shares)} Lido adapter shares`);
  const tx = await claimBaseAssetWithdrawal({
    baseContext,
    signer,
    shares,
  });
  await logTxDetails(tx, "claimRedeem");
};

module.exports = {
  requestLidoWithdrawals,
  claimLidoWithdrawals,
};
