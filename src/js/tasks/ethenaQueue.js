const { formatUnits, parseUnits } = require("ethers");
const { ethers } = require("ethers");

const { baseWithdrawAmount } = require("./liquidityAutomation");
const { adapterContract, resolveArmBase } = require("../utils/arm");
const { logTxDetails } = require("../utils/txLogger");
const log = require("../utils/logger")("task:ethenaQueue");

const requestEthenaWithdrawals = async (options) => {
  const { signer, arm, amount } = options;
  const { baseAddress, config } = await resolveArmBase(options);
  const adapter = await adapterContract(config.adapter, signer);

  // 1. Determine withdrawal amount: Explicit Input OR calculate from ARM and lending market balances
  const withdrawAmount = amount
    ? parseUnits(amount.toString())
    : await baseWithdrawAmount(options);
  if (!withdrawAmount || withdrawAmount === 0n) return;

  // 2. Check the contract request delay has passed since the last withdrawal request
  const lastRequestTime = await adapter.lastRequestTimestamp();
  const requestDelay = Number(await adapter.DELAY_REQUEST());
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
  const tx = await arm
    .connect(signer)
    .requestRedeem(baseAddress, withdrawAmount);
  await logTxDetails(tx, "requestEthenaWithdrawal");
};

// --- CONSTANTS ---
const SUSDE_ADDRESS = "0x9D39A5DE30e57443BfF2A8307A4256c8797A3497";
const SUSDE_ABI = [
  "function cooldowns(address) view returns (uint104,uint152)",
];

// --- HELPER: CORE LOGIC ---
// Fetches data for a list of addresses in PARALLEL (much faster)
const fetchUnstakerStates = async (signer, adapter, addresses) => {
  const contract = new ethers.Contract(SUSDE_ADDRESS, SUSDE_ABI, signer);
  const { timestamp: currentTimestamp } =
    await signer.provider.getBlock("latest");

  if (!addresses) {
    const pendingLength = await adapter.pendingUnstakerIndexesLength();
    addresses = await Promise.all(
      Array.from({ length: Number(pendingLength) }, async (_, pendingIndex) => {
        const index = await adapter.pendingUnstakerIndex(pendingIndex);
        const address = await adapter.unstakers(index);
        return { address, index: Number(index) };
      }),
    );
  } else {
    addresses = await Promise.all(
      addresses.map(async (address) => ({
        address,
        index: Number.MAX_SAFE_INTEGER,
      })),
    );
  }

  // Promise.all executes all RPC calls simultaneously
  return Promise.all(
    addresses.map(async ({ address, index }) => {
      const [cooldownEnd, underlyingAmount] = await contract.cooldowns(address);
      const shares = await adapter["requestShares(address)"](address);
      const expectedAssets = await adapter["requestAssets(address)"](address);
      const amountStr = formatUnits(underlyingAmount, 18);
      const isBalancePositive = underlyingAmount > 0 || shares > 0;

      let timeLeft = "None";
      let isReady = false;

      if (isBalancePositive) {
        if (cooldownEnd < currentTimestamp) {
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
        rawAmount: underlyingAmount, // Keep BigNumber for calculations
        shares,
        expectedAssets,
        amount: amountStr, // String for display
        hasBalance: isBalancePositive,
        isReady,
        timeLeft,
      };
    }),
  );
};

// --- MAIN FUNCTIONS ---
const ethenaWithdrawStatus = async (options) => {
  const { signer } = options;
  const { config } = await resolveArmBase(options);
  const adapter = await adapterContract(config.adapter, signer);

  // Reuse the core logic
  const allStates = await fetchUnstakerStates(signer, adapter);

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
      )} shares, ${formatUnits(u.expectedAssets)} expected USDe, ${u.amount} cooldown USDe\t| Status: ${fifoStatus}`,
    );
  });

  return active;
};

const claimEthenaWithdrawals = async (options) => {
  const { arm, signer } = options;
  const { baseAddress, config } = await resolveArmBase(options);
  const adapter = await adapterContract(config.adapter, signer);

  log(`Checking Ethena adapter withdrawal status...`);

  // 1. Fetch all data in parallel first (Fast)
  const states = await fetchUnstakerStates(signer, adapter);

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

    let shares = 0n;
    for (const item of claimable) {
      log(
        ` - Claimable index ${item.index}, ${item.amount} USDe and address ${item.address}`,
      );
      shares += item.shares;
    }

    const tx = await arm.connect(signer).claimRedeem(baseAddress, shares);
    await logTxDetails(tx, `claimEthenaWithdrawal`);
  } else {
    log("No ready USDe withdrawal requests found.");
  }
};

const selectClaimableFifoPrefix = (states) => {
  const firstUnreadyIndex = states.findIndex((s) => !s.isReady);
  if (firstUnreadyIndex === -1) return states;
  return states.slice(0, firstUnreadyIndex);
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
  selectClaimableFifoPrefix,
};
