const { formatUnits, parseUnits } = require("ethers");
const dayjs = require("dayjs");
const utc = require("dayjs/plugin/utc");

const { getBlock } = require("../utils/block");
const { parseAddress } = require("../utils/addressParser");
const { resolveAsset } = require("../utils/assets");
const { outstandingWithdrawalAmount } = require("../utils/armQueue");
const { logArmPrices } = require("./markets");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:liquidity");

// Extend Day.js with the UTC plugin
dayjs.extend(utc);

const requestWithdraw = async ({ amount, signer, armName, arm }) => {
  const amountBI = parseUnits(amount.toString(), 18);

  log(`About to request ${amount} OETH withdrawal`);

  const functionName =
    armName == "Origin" ? "requestOriginWithdrawal" : "requestWithdrawal";
  const tx = await arm.connect(signer)[functionName](amountBI);

  await logTxDetails(tx, functionName);

  // TODO parse the request id from the WithdrawalRequested event on the OETH Vault
};

const claimWithdraw = async ({ id, signer, armName, arm }) => {
  const functionName =
    armName == "Origin" ? "claimOriginWithdrawals" : "claimWithdrawals";
  const tx = await arm.connect(signer)[functionName]([id]);

  log(`About to claim withdrawal request ${id} calling ${functionName}`);
  await logTxDetails(tx, functionName);
};

const withdrawRequestStatus = async ({ id, arm, vault }) => {
  const queue = await vault.withdrawalQueueMetadata();
  const request = await arm.withdrawalRequests(id);

  if (request.queued <= queue.claimable) {
    console.log(`Withdrawal request ${id} is claimable.`);
  } else {
    console.log(
      `Withdrawal request ${id} is ${formatUnits(
        request.queued - queue.claimable
      )} short`
    );
  }
};

const snap = async ({ arm, block }) => {
  const armAddress = await parseAddress(`${arm.toUpperCase()}_ARM`);
  const armContract = await ethers.getContractAt(`${arm}ARM`, armAddress);

  const blockTag = await getBlock(block);

  const { liquidityBalance } = await logLiquidity({ arm, block });

  if (arm !== "Oeth") {
    await logWithdrawalQueue(armContract, blockTag, liquidityBalance);

    await logArmPrices({ block }, armContract);
  }
};

const logLiquidity = async ({ block, arm }) => {
  const blockTag = await getBlock(block);
  console.log(`\nLiquidity`);

  const armAddress = await parseAddress(`${arm.toUpperCase()}_ARM`);
  const armContract = await ethers.getContractAt(`${arm}ARM`, armAddress);

  const liquiditySymbol = arm === "Origin" ? "WS" : "WETH";
  const liquidAsset = await resolveAsset(liquiditySymbol);
  const liquidityBalance = await liquidAsset.balanceOf(armAddress, {
    blockTag,
  });

  const baseSymbol = arm === "Origin" ? "OS" : "OETH";
  const baseAsset = await resolveAsset(baseSymbol);
  const baseBalance = await baseAsset.balanceOf(armAddress, { blockTag });
  const baseWithdraws = await outstandingWithdrawalAmount({
    withdrawer: armAddress,
  });

  let lendingMarketBalance = 0n;
  if (arm === "Origin") {
    // Get the lending market from the active SiloMarket
    const marketAddress = await armContract.activeMarket({ blockTag });
    const market = await ethers.getContractAt("SiloMarket", marketAddress);
    const armShares = await market.balanceOf(armAddress, { blockTag });
    lendingMarketBalance = await market.convertToAssets(armShares, {
      blockTag,
    });
  }

  const total =
    liquidityBalance + baseBalance + baseWithdraws + lendingMarketBalance;
  const liquidityPercent = total == 0 ? 0 : (liquidityBalance * 10000n) / total;
  const baseWithdrawsPercent =
    total == 0 ? 0 : (baseWithdraws * 10000n) / total;
  const basePercent = total == 0 ? 0 : (baseBalance * 10000n) / total;
  const lendingMarketPercent =
    total == 0 ? 0 : (lendingMarketBalance * 10000n) / total;

  const totalAssets = await armContract.totalAssets({ blockTag });
  const accruedFees = await armContract.feesAccrued({ blockTag });

  console.log(
    `${formatUnits(liquidityBalance, 18)} ${liquiditySymbol} ${formatUnits(
      liquidityPercent,
      2
    )}%`
  );
  console.log(
    `${formatUnits(baseBalance, 18)} ${baseSymbol} ${formatUnits(
      basePercent,
      2
    )}%`
  );
  console.log(
    `${formatUnits(
      baseWithdraws,
      18
    )} ${baseSymbol} in withdrawal requests ${formatUnits(
      baseWithdrawsPercent,
      2
    )}%`
  );
  console.log(
    `${formatUnits(
      lendingMarketBalance,
      18
    )} ${liquiditySymbol} in active lending market ${formatUnits(
      lendingMarketPercent,
      2
    )}%`
  );
  console.log(`${formatUnits(total, 18)} raw total assets`);

  console.log(`${formatUnits(accruedFees, 18)} accrued fees`);
  console.log(`${formatUnits(totalAssets, 18)} total assets`);

  return { total, liquidityBalance };
};

const logWithdrawalQueue = async (arm, blockTag, liquidityWeth) => {
  const queue = await arm.withdrawsQueued({
    blockTag,
  });
  const claimed = await arm.withdrawsClaimed({ blockTag });
  const outstanding = queue - claimed;
  const available = liquidityWeth - outstanding;

  console.log(`\nARM Withdrawal Queue`);
  console.log(`${formatUnits(outstanding, 18).padEnd(23)} outstanding`);
  console.log(`${formatUnits(available, 18).padEnd(23)} available`);
};

module.exports = {
  snap,
  logLiquidity,
  logWithdrawalQueue,
  requestWithdraw,
  claimWithdraw,
  withdrawRequestStatus,
};
