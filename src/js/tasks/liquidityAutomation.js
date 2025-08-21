const { formatUnits, parseUnits } = require("ethers");
const dayjs = require("dayjs");
const utc = require("dayjs/plugin/utc");

const { claimableRequests } = require("../utils/armQueue");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:liquidity");

// Extend Day.js with the UTC plugin
dayjs.extend(utc);

const autoRequestWithdraw = async ({
  signer,
  asset,
  arm,
  minAmount,
  confirm,
}) => {
  const symbol = await asset.symbol();
  const assetBalance = await asset.balanceOf(await arm.getAddress());
  log(`${formatUnits(assetBalance)} ${symbol} in ARM`);

  const minAmountBI = parseUnits(minAmount.toString(), 18);

  if (assetBalance <= minAmountBI) {
    console.log(
      `${formatUnits(
        assetBalance
      )} ${symbol} is below ${minAmount} so not withdrawing`
    );
    return;
  }

  log(`About to request ${formatUnits(assetBalance)} ${symbol} withdrawal`);

  const functionName =
    symbol == "OS" ? "requestOriginWithdrawal" : "requestWithdrawal";
  const tx = await arm.connect(signer)[functionName](assetBalance);
  await logTxDetails(tx, "requestWithdrawal", confirm);
};

const autoClaimWithdraw = async ({
  signer,
  liquidityAsset,
  arm,
  vault,
  confirm,
}) => {
  const liquiditySymbol = await liquidityAsset.symbol();
  // Get amount of requests that have already been claimed
  const { claimed } = await vault.withdrawalQueueMetadata();

  // Get liquidity balance in the Vault
  const vaultLiquidity = await liquidityAsset.balanceOf(
    await vault.getAddress()
  );

  const queuedAmountClaimable = claimed + vaultLiquidity;
  log(
    `Claimable queued amount is ${formatUnits(claimed)} claimed + ${formatUnits(
      vaultLiquidity
    )} ${liquiditySymbol} in vault = ${formatUnits(queuedAmountClaimable)}`
  );

  // Get the Date time of 10 minutes ago
  const now = dayjs();
  const claimDelaySeconds = await vault.withdrawalClaimDelay();
  const claimCutoff = now.subtract(Number(claimDelaySeconds), "seconds");
  log(
    `${claimDelaySeconds} second claim delay gives claim cutoff timestamp: ${claimCutoff.unix()} ${claimCutoff.toISOString()}`
  );

  // get claimable withdrawal requests
  let requestIds = await claimableRequests({
    withdrawer: await arm.getAddress(),
    queuedAmountClaimable,
    claimCutoff,
  });

  if (requestIds.length === 0) {
    log("No claimable requests");
    return requestIds;
  }

  log(`About to claim requests: ${requestIds} `);

  const functionName =
    liquiditySymbol == "wS" ? "claimOriginWithdrawals" : "claimWithdrawals";
  const tx = await arm.connect(signer)[functionName](requestIds);
  await logTxDetails(tx, "claimWithdrawals", confirm);

  return requestIds;
};

module.exports = {
  autoRequestWithdraw,
  autoClaimWithdraw,
};
