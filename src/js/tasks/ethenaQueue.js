const { formatUnits, parseUnits } = require("ethers");
const { ethers } = require("ethers");

const { baseWithdrawAmount } = require("./liquidityAutomation");
const {
  adapterContract,
  claimBaseAssetWithdrawal,
  requestBaseAssetWithdrawal,
  resolveArmBase,
} = require("../utils/arm");
const {
  isEthenaRequestReady,
  orderPendingUnstakerStates,
  selectClaimableFifoPrefix,
} = require("../utils/ethenaQueue");
const { logTxDetails } = require("../utils/txLogger");
const log = require("../utils/logger")("task:ethenaQueue");

const requestEthenaWithdrawals = async (options) => {
  const { signer, amount } = options;
  const baseContext = await resolveArmBase(options);
  const requestDelayContract =
    baseContext.version === "legacy"
      ? baseContext.compatibleArm.connect(signer)
      : await adapterContract(baseContext.config.adapter, signer);

  // 1. Determine withdrawal amount: Explicit Input OR calculate from ARM and lending market balances
  const withdrawAmount = amount
    ? parseUnits(amount.toString())
    : await baseWithdrawAmount(options);
  if (!withdrawAmount || withdrawAmount === 0n) return;

  // 2. Check the contract request delay has passed since the last withdrawal request
  const lastRequestTime = await requestDelayContract.lastRequestTimestamp();
  const requestDelay = Number(await requestDelayContract.DELAY_REQUEST());
  const currentTime = Math.floor(Date.now() / 1000);
  const timeSinceLastRequest = currentTime - Number(lastRequestTime);
  if (timeSinceLastRequest < requestDelay) {
    const timeLeft = requestDelay - timeSinceLastRequest;
    log(
      `Skipping: Last withdrawal request was only ${timeSinceLastRequest} seconds ago; need to wait another ${timeLeft} seconds`,
    );
    return;
  }

  // 3. Execution
  log(`Requesting withdrawal for ${formatUnits(withdrawAmount)} sUSDe...`);
  const tx = await requestBaseAssetWithdrawal({
    baseContext,
    signer,
    amount: withdrawAmount,
  });
  await logTxDetails(tx, "requestEthenaWithdrawal");
};

// --- CONSTANTS ---
const SUSDE_ADDRESS = "0x9D39A5DE30e57443BfF2A8307A4256c8797A3497";
const SUSDE_ABI = [
  "function cooldownDuration() view returns (uint24)",
  "function cooldowns(address) view returns (uint104,uint152)",
];

const legacyEthenaUnstakers = async (legacyArm, blockTag) => {
  const unstakers = [];
  for (let i = 0; ; i++) {
    try {
      const unstaker = await legacyArm.unstakers(i, blockTag);
      if (unstaker === ethers.ZeroAddress) break;
      unstakers.push({ address: unstaker, index: i });
    } catch {
      break;
    }
  }
  return unstakers;
};

// --- HELPER: CORE LOGIC ---
// Fetches data for a list of addresses in PARALLEL (much faster)
const fetchUnstakerStates = async (signer, adapter, legacyArm) => {
  const contract = new ethers.Contract(SUSDE_ADDRESS, SUSDE_ABI, signer);
  // Pin all queue reads to one block. Reading each value at `latest` can mix
  // state from a concurrent request or claim and produce an impossible FIFO
  // snapshot.
  const blockNumber = await signer.provider.getBlockNumber();
  const blockTag = { blockTag: blockNumber };
  const { timestamp: currentTimestamp } =
    await signer.provider.getBlock(blockNumber);
  let requestCount;
  let maxUnstakers;

  const duration = await contract.cooldownDuration(blockTag);
  let addresses;
  if (adapter) {
    [requestCount, maxUnstakers] = await Promise.all([
      adapter.totalRequests(blockTag),
      adapter.MAX_UNSTAKERS(blockTag),
    ]);
    const unstakerCount = Number(
      requestCount < maxUnstakers ? requestCount : maxUnstakers,
    );
    addresses = await Promise.all(
      Array.from({ length: unstakerCount }, async (_, index) => {
        const address = await adapter.unstakers(index, blockTag);
        return { address, index };
      }),
    );
  } else {
    addresses = await legacyEthenaUnstakers(legacyArm, blockTag);
  }

  // Promise.all executes all RPC calls simultaneously
  const states = await Promise.all(
    addresses.map(async ({ address, index }) => {
      const [cooldownEnd, underlyingAmount] = await contract.cooldowns(
        address,
        blockTag,
      );
      const shares = adapter
        ? await adapter["requestShares(address)"](address, blockTag)
        : underlyingAmount;
      const expectedAssets = adapter
        ? await adapter["requestAssets(address)"](address, blockTag)
        : underlyingAmount;
      const prefunded =
        adapter &&
        shares > 0n &&
        (await adapter.isPrefunded(address, blockTag));
      const rawAmount = prefunded ? expectedAssets : underlyingAmount;
      const amountStr = formatUnits(rawAmount, 18);
      const isBalancePositive = underlyingAmount > 0 || shares > 0;

      let timeLeft = "None";
      let isReady = false;

      if (isBalancePositive) {
        if (
          isEthenaRequestReady(
            prefunded,
            duration,
            cooldownEnd,
            currentTimestamp,
          )
        ) {
          isReady = true;
          timeLeft = "Ready to Claim";
        } else {
          const nowMs = new Date(currentTimestamp * 1000);
          const endMs = new Date(Number(cooldownEnd) * 1000);
          timeLeft = getTimeDifference(nowMs, endMs);
        }
      }

      return {
        address,
        index, // Index in the unstakers array
        rawAmount,
        prefunded,
        shares,
        expectedAssets,
        amount: amountStr, // String for display
        hasBalance: isBalancePositive,
        isReady,
        timeLeft,
      };
    }),
  );

  if (!adapter) return states;

  return orderPendingUnstakerStates(
    states,
    requestCount,
    maxUnstakers,
    blockNumber,
  );
};

// --- MAIN FUNCTIONS ---
const ethenaWithdrawStatus = async (options) => {
  const { signer } = options;
  const baseContext = await resolveArmBase(options);
  const adapter =
    baseContext.version === "legacy"
      ? undefined
      : await adapterContract(baseContext.config.adapter, signer);

  // Reuse the core logic
  const allStates = await fetchUnstakerStates(
    signer,
    adapter,
    baseContext.version === "legacy" ? baseContext.compatibleArm : undefined,
  );

  // Filter and Log
  const active = allStates.filter((s) => s.hasBalance);
  const claimable = selectClaimableFifoPrefix(active);
  const claimableSet = new Set(claimable.map((s) => s.address));
  const firstBlocked = active.find((s) => !s.isReady);

  log(`Found ${active.length} active unstakers:`);
  active.forEach((u) => {
    const fifoStatus = claimableSet.has(u.address)
      ? "claimable"
      : u.isReady && firstBlocked
        ? "ready but FIFO-blocked"
        : u.timeLeft;
    log(
      ` - index ${u.index}, ${u.address}: ${formatUnits(
        u.shares,
      )} shares, ${formatUnits(u.expectedAssets)} expected USDe, ${u.amount} ${u.prefunded ? "prefunded" : "cooldown"} USDe\t| Status: ${fifoStatus}`,
    );
  });

  return active;
};

const claimEthenaWithdrawals = async (options) => {
  const { signer } = options;
  const baseContext = await resolveArmBase(options);
  const adapter =
    baseContext.version === "legacy"
      ? undefined
      : await adapterContract(baseContext.config.adapter, signer);

  log(`Checking Ethena adapter withdrawal status...`);

  // 1. Fetch all data in parallel first (Fast)
  const states = await fetchUnstakerStates(
    signer,
    adapter,
    baseContext.version === "legacy" ? baseContext.compatibleArm : undefined,
  );

  // 2. Log status for everyone
  states.forEach((s) => {
    if (s.hasBalance && !s.isReady) {
      log(
        `Unstaker ${s.address} cooldown not completed; ending in ${s.timeLeft}`,
      );
    }
  });

  // 3. Filter who is ready to claim. Adapter claims are FIFO, so only
  // claim a contiguous ready prefix.
  const activeStates = states.filter((s) => s.hasBalance && s.shares > 0n);
  const claimable = selectClaimableFifoPrefix(activeStates);

  // 4. Execute Claims
  if (claimable.length > 0) {
    log(`About to claim ${claimable.length} withdrawal requests...`);

    if (baseContext.version === "legacy") {
      for (const item of claimable) {
        log(
          ` - Processing claim for index ${item.index}, ${item.amount} USDe and address ${item.address}`,
        );
        const tx = await claimBaseAssetWithdrawal({
          baseContext,
          signer,
          unstakerIndex: item.index,
        });
        await logTxDetails(tx, `claimEthenaWithdrawal for ${item.address}`);
      }
      return;
    }

    let shares = 0n;
    for (const item of claimable) {
      log(
        ` - Claimable index ${item.index}, ${item.amount} USDe and address ${item.address}`,
      );
      shares += item.shares;
    }

    const tx = await claimBaseAssetWithdrawal({
      baseContext,
      signer,
      shares,
    });
    await logTxDetails(tx, `claimEthenaWithdrawal`);
  } else {
    log("No ready USDe withdrawal requests found.");
  }
};

// --- UTILS ---
function getTimeDifference(date1, date2) {
  const diff = Math.abs(new Date(date2) - new Date(date1));
  const d = Math.floor(diff / (1000 * 60 * 60 * 24));
  const h = Math.floor((diff / (1000 * 60 * 60)) % 24);
  const m = Math.floor((diff / (1000 * 60)) % 60);
  const s = Math.floor((diff / 1000) % 60);
  return `${d}d ${h}h ${m}m ${s}s`;
}

module.exports = {
  requestEthenaWithdrawals,
  claimEthenaWithdrawals,
  ethenaWithdrawStatus,
  orderPendingUnstakerStates,
  selectClaimableFifoPrefix,
};
