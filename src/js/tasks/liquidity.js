const { formatUnits, parseUnits } = require("ethers");

const { parseAddress } = require("../utils/addressParser");
const { resolveAsset } = require("../utils/assets");
const {
  claimableRequests,
  outstandingWithdrawalAmount,
} = require("../utils/queue");
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
  oeth,
  oethARM,
  minAmount,
  confirm,
}) => {
  const oethBalance = await oeth.balanceOf(await oethARM.getAddress());
  log(`${formatUnits(oethBalance)} OETH in ARM`);

  const minAmountBI = parseUnits(minAmount.toString(), 18);

  if (oethBalance <= minAmountBI) {
    console.log(
      `${formatUnits(
        oethBalance
      )} OETH is below ${minAmount} so not withdrawing`
    );
    return;
  }

  log(`About to request ${formatUnits(oethBalance)} OETH withdrawal`);

  const tx = await oethARM.connect(signer).requestWithdrawal(oethBalance);
  await logTxDetails(tx, "requestWithdrawal", confirm);
};

const autoClaimWithdraw = async ({ signer, weth, oethARM, vault, confirm }) => {
  // Get amount of requests that have already been claimed
  const { claimed } = await vault.withdrawalQueueMetadata();

  // Get WETH balance in OETH Vault
  const wethVaultBalance = await weth.balanceOf(await vault.getAddress());

  const queuedAmountClaimable = claimed + wethVaultBalance;
  log(
    `Claimable queued amount is ${formatUnits(claimed)} claimed + ${formatUnits(
      wethVaultBalance
    )} WETH in vault = ${formatUnits(queuedAmountClaimable)}`
  );

  // get claimable withdrawal requests
  let requestIds = await claimableRequests({
    withdrawer: await oethARM.getAddress(),
    queuedAmountClaimable,
  });

  log(`About to claim requests: ${requestIds} `);

  if (requestIds.length > 0) {
    const tx = await oethARM.connect(signer).claimWithdrawals(requestIds);
    await logTxDetails(tx, "claimWithdrawals", confirm);
  }
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

const logLiquidity = async () => {
  console.log(`\nLiquidity`);

  const oethArmAddress = await parseAddress("OETH_ARM");
  const oethARM = await ethers.getContractAt("OethARM", oethArmAddress);

  const weth = await resolveAsset("WETH");
  const liquidityWeth = await weth.balanceOf(await oethARM.getAddress());

  const oeth = await resolveAsset("OETH");
  const liquidityOeth = await oeth.balanceOf(await oethARM.getAddress());
  const liquidityOethWithdraws = await outstandingWithdrawalAmount({
    withdrawer: await oethARM.getAddress(),
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
