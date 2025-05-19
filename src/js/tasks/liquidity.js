const { formatUnits, parseUnits } = require("ethers");

const { getBlock } = require("../utils/block");
const { parseAddress } = require("../utils/addressParser");
const { resolveAsset } = require("../utils/assets");
const {
  claimableRequests,
  outstandingWithdrawalAmount,
} = require("../utils/armQueue");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:liquidity");

const requestWithdraw = async ({ amount, signer, oethARM }) => {
  const amountBI = parseUnits(amount.toString(), 18);

  log(`About to request ${amount} OETH withdrawal`);

  const tx = await oethARM.connect(signer).requestWithdrawal(amountBI);

  await logTxDetails(tx, "requestWithdrawal");

  // TODO parse the request id from the WithdrawalRequested event on the OETH Vault
};

const claimWithdraw = async ({ id, signer, oethARM }) => {
  log(`About to claim withdrawal request ${id}`);

  const tx = await oethARM.connect(signer).claimWithdrawal(id);

  await logTxDetails(tx, "claimWithdrawal");
};

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

  // get claimable withdrawal requests
  let requestIds = await claimableRequests({
    withdrawer: await arm.getAddress(),
    queuedAmountClaimable,
  });

  if (requestIds.length === 0) {
    log("No claimable requests");
    return;
  }

  log(`About to claim requests: ${requestIds} `);

  const functionName =
    liquiditySymbol == "wS" ? "claimOriginWithdrawals" : "claimWithdrawals";
  const tx = await arm.connect(signer)[functionName](requestIds);
  await logTxDetails(tx, "claimWithdrawals", confirm);
};

const withdrawRequestStatus = async ({ id, oethARM, vault }) => {
  const queue = await vault.withdrawalQueueMetadata();
  const request = await oethARM.withdrawalRequests(id);

  if (request.queued <= queue.claimable) {
    console.log(`Withdrawal request ${id} is claimable.`);
  } else {
    console.log(
      `Withdrawal request ${id} is ${formatUnits(
        request.queued - queue.claimable
      )} WETH short`
    );
  }
};

const logLiquidity = async ({ block }) => {
  const blockTag = await getBlock(block);
  console.log(`\nLiquidity`);

  const oethArmAddress = await parseAddress("OETH_ARM");

  const weth = await resolveAsset("WETH");
  const liquidityWeth = await weth.balanceOf(oethArmAddress, { blockTag });

  const oeth = await resolveAsset("OETH");
  const liquidityOeth = await oeth.balanceOf(oethArmAddress, { blockTag });
  const liquidityOethWithdraws = await outstandingWithdrawalAmount({
    withdrawer: oethArmAddress,
  });

  const total = liquidityWeth + liquidityOeth + liquidityOethWithdraws;
  const wethPercent = total == 0 ? 0 : (liquidityWeth * 10000n) / total;
  const oethWithdrawsPercent =
    total == 0 ? 0 : (liquidityOethWithdraws * 10000n) / total;
  const oethPercent = total == 0 ? 0 : (liquidityOeth * 10000n) / total;

  console.log(
    `${formatUnits(liquidityWeth, 18)} WETH ${formatUnits(wethPercent, 2)}%`
  );
  console.log(
    `${formatUnits(liquidityOeth, 18)} OETH ${formatUnits(oethPercent, 2)}%`
  );
  console.log(
    `${formatUnits(
      liquidityOethWithdraws,
      18
    )} OETH in withdrawal requests ${formatUnits(oethWithdrawsPercent, 2)}%`
  );
  console.log(`${formatUnits(total, 18)} total WETH and OETH`);
};

module.exports = {
  autoRequestWithdraw,
  autoClaimWithdraw,
  logLiquidity,
  requestWithdraw,
  claimWithdraw,
  withdrawRequestStatus,
};
