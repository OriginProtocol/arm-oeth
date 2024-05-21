const { formatUnits, parseUnits } = require("ethers");

const addresses = require("../utils/addresses");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:liquidity");

const withdrawStEth = async (options) => {
  const { amount, signer, oSwap } = options;

  const amountBI = parseUnits(amount.toString(), 18);

  log(`About to request ${amount} stETH withdrawal from Lido`);

  const tx = await oSwap
    .connect(signer)
    .requestStETHWithdrawalForETH([amountBI]);

  await logTxDetails(tx, "requestStETHWithdrawalForETH", options.confirm);
};

const autoWithdraw = async (options) => {
  const { signer, stEth, weth, oSwap, minAmount, divisor } = options;

  const liquidityStEth = await stEth.balanceOf(addresses.mainnet.OEthARM);
  log(`${formatUnits(liquidityStEth)} stETH AMM liquidity`);

  const liquidityWeth = await weth.balanceOf(addresses.mainnet.OEthARM);
  log(`${formatUnits(liquidityWeth)} WETH AMM liquidity`);

  const liquidityStEthWithdraws = await getWithdrawRequestLiquidity(options);

  // stETH is targeted to default to 1/3 of the liquidity
  const targetStEthLiquidity =
    (liquidityStEth + liquidityWeth + liquidityStEthWithdraws) /
    (divisor || 3n);
  log(`${formatUnits(targetStEthLiquidity)} target liquidity`);

  const withdrawAmount = liquidityStEth - targetStEthLiquidity;
  log(`${formatUnits(withdrawAmount)} stETH withdraw amount`);

  const minAmountBI = parseUnits(minAmount.toString(), 18);

  if (withdrawAmount <= minAmountBI) {
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

  const tx = await oSwap
    .connect(signer)
    .requestStETHWithdrawalForETH([withdrawAmount]);

  await logTxDetails(tx, "requestStETHWithdrawalForETH", options.confirm);
};

const withdrawStEthStatus = async (options) => {
  const { id } = options;

  const stEthWithdrawQueue = await hre.ethers.getContractAt(
    "IStETHWithdrawal",
    addresses.mainnet.stETHWithdrawalQueue
  );

  const status = await stEthWithdrawQueue.getWithdrawalStatus([id]);

  console.log(
    `Withdrawal request ${id} is finalized ${status[0].isFinalized} and claimed ${status[0].isClaimed}`
  );
};

const autoClaim = async (options) => {
  const { signer, oethARM, oethVault } = options;

  // Get the outstanding withdrawal requests for the AMM
  const requestIds = await oethVault.getWithdrawalRequests(oethARM.address);
  log(`Found ${requestIds.length} withdrawal requests`);

  if (requestIds.length === 0) {
    return;
  }

  const statuses = await oethVault.getWithdrawalStatus([...requestIds]);
  log(`Got ${statuses.length} statuses`);

  const finalizedIds = [];

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
    const tx = await oSwap.connect(signer).claimWithdrawal(sortedFinalizedIds);
    await logTxDetails(tx, "claim withdraw requests", options.confirm);
  } else {
    log("No finalized withdrawal requests to claim");
  }
};

const getWithdrawRequestLiquidity = async ({ withdrawalQueue }) => {
  const requests = await withdrawalQueue.getWithdrawalRequests(
    addresses.mainnet.OEthARM
  );
  log(`Found ${requests.length} withdrawal requests`);

  let total = 0n;
  for (const request of requests) {
    const status = await withdrawalQueue.getWithdrawalStatus([request]);
    log(`Withdrawal request ${request} status ${status[0].isClaimed}`);
    if (!status[0].isClaimed) {
      total += status[0].amountOfStETH;
    }
  }
  return total;
};

const logLiquidity = async (options) => {
  console.log(`\nLiquidity`);

  const weth = await ethers.getContractAt("IERC20", addresses.mainnet.WETH);
  const liquidityWeth = await weth.balanceOf(addresses.mainnet.OEthARM);

  const stEth = await ethers.getContractAt("IERC20", addresses.mainnet.stETH);
  const liquidityStEth = await stEth.balanceOf(addresses.mainnet.OEthARM);
  const withdrawalQueue = await hre.ethers.getContractAt(
    "IStETHWithdrawal",
    addresses.mainnet.stETHWithdrawalQueue
  );
  const liquidityStEthWithdraws = await getWithdrawRequestLiquidity({
    withdrawalQueue,
  });

  const total = liquidityWeth + liquidityStEth + liquidityStEthWithdraws;
  const wethPercent = (liquidityWeth * 10000n) / total;
  const stEthWithdrawsPercent = (liquidityStEthWithdraws * 10000n) / total;
  const stEthPercent = (liquidityStEth * 10000n) / total;
  const startTotal = parseUnits(options.start.toString(), 18);
  const profit = total - startTotal;

  console.log(
    `${formatUnits(liquidityWeth, 18)} WETH ${formatUnits(wethPercent, 2)}%`
  );
  console.log(
    `${formatUnits(liquidityStEth, 18)} stETH ${formatUnits(stEthPercent, 2)}%`
  );
  console.log(
    `${formatUnits(
      liquidityStEthWithdraws,
      18
    )} stETH in withdrawal requests ${formatUnits(stEthWithdrawsPercent, 2)}%`
  );
  console.log(`${formatUnits(total, 18)} ETH, profit ${formatUnits(profit)}`);
};

module.exports = {
  autoClaim,
  autoWithdraw,
  logLiquidity,
  withdrawStEth,
  withdrawStEthStatus,
};
