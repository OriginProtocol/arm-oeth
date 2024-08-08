const { formatUnits, parseUnits } = require("ethers");

const { parseAddress } = require("../utils/addressParser");
const { resolveAsset } = require("../utils/assets");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:liquidity");

const requestWithdraw = async (options) => {
  const { amount, signer, oethARM } = options;

  const amountBI = parseUnits(amount.toString(), 18);

  log(`About to request ${amount} OETH withdrawal`);

  const tx = await oethARM.connect(signer).requestWithdrawal(amountBI);

  await logTxDetails(tx, "requestWithdrawal");
};

const claimWithdraw = async ({ id, signer, oethARM }) => {
  log(`About to claim withdrawal request ${id}`);

  const tx = await oethARM.connect(signer).claimWithdrawal(id);

  await logTxDetails(tx, "claimWithdrawal");
};

const autoWithdraw = async (options) => {
  const { signer, oeth, oethARM, minAmount } = options;

  const oethArmAddr = oethARM.getAddress();
  const oethBalance = await oeth.balanceOf(oethArmAddr);
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

  await logTxDetails(tx, "requestWithdrawal", options.confirm);
};

const withdrawRequestStatus = async (options) => {
  const { id, oethARM } = options;

  const queue = await oethARM.withdrawalQueueMetadata();
  const request = await oethARM.withdrawalRequests(id);

  if (request.queued <= queue.claimable) {
    console.log(`Withdrawal request ${id} is claimable.`);
  } else {
    console.log(
      `Withdrawal request ${id} is ${formatUnits(
        request.queued.sub(queue.claimable)
      )} WETH short`
    );
  }
};

const logLiquidity = async () => {
  console.log(`\nLiquidity`);

  const oethArmAddress = await parseAddress("OETH_ARM");
  const oethARM = await ethers.getContractAt("OEthARM", oethArmAddress);

  const weth = await resolveAsset("WETH");
  const liquidityWeth = await weth.balanceOf(oethARM.getAddress());

  const oeth = await resolveAsset("OETH");
  const liquidityOeth = await oeth.balanceOf(oethARM.getAddress());
  // TODO need to get from indexer
  const liquidityOethWithdraws = 0n;

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
};

module.exports = {
  autoWithdraw,
  logLiquidity,
  requestWithdraw,
  claimWithdraw,
  withdrawRequestStatus,
};
