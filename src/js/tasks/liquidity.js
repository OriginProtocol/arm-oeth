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
  log(`About to claim withdrawal request ${id}`);

  const functionName =
    armName == "Origin" ? "claimOriginWithdrawal" : "claimWithdrawal";
  const tx = await arm.connect(signer)[functionName](id);

  await logTxDetails(tx, functionName);
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
    return requestIds;
  }

  log(`About to claim requests: ${requestIds} `);

  const functionName =
    liquiditySymbol == "wS" ? "claimOriginWithdrawals" : "claimWithdrawals";
  const tx = await arm.connect(signer)[functionName](requestIds);
  await logTxDetails(tx, "claimWithdrawals", confirm);

  return requestIds;
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
  console.log(`${formatUnits(total, 18)} total`);
};


const logWithdrawalQueue = async (arm, blockTag, liquidityWeth) => {
  const queue = await arm.withdrawsQueued({
    blockTag,
  });
  const claimed = await arm.withdrawsClaimed({ blockTag });
  const outstanding = queue - claimed;
  const shortfall =
    liquidityWeth < outstanding ? liquidityWeth - outstanding : 0;

  console.log(`\nARM Withdrawal Queue`);
  console.log(`${formatUnits(outstanding, 18).padEnd(23)} outstanding`);
  console.log(`${formatUnits(shortfall, 18).padEnd(23)} shortfall`);
};

module.exports = {
  autoRequestWithdraw,
  autoClaimWithdraw,
  logLiquidity,
  logWithdrawalQueue,
  requestWithdraw,
  claimWithdraw,
  withdrawRequestStatus,
};
