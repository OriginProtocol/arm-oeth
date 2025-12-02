const { formatUnits, parseUnits } = require("ethers");
const { logTxDetails } = require("../utils/txLogger");
const log = require("../utils/logger")("task:ethenaQueue");

const requestEthenaWithdrawals = async (options) => {
  const { signer, susde, arm, amount, minAmount } = options;

  // 1. Resolve ARM Address (Supports Ethers v5 & v6)
  const armAddress = arm.target || arm.address || (await arm.getAddress());

  // 2. Determine Amount: Explicit Input OR Full Balance
  const withdrawAmount = amount
    ? parseUnits(amount.toString())
    : await susde.balanceOf(armAddress);

  const formattedAmount = formatUnits(withdrawAmount);
  const minAmountBI = parseUnits(minAmount.toString());

  // 3. Checks & validations

  // Safety check: Never try to withdraw 0
  if (withdrawAmount == 0) {
    log("Skipping withdrawal: Balance is 0 sUSDe");
    return;
  }

  // Minimum check (only applies if we are sweeping the full balance, not if amount is manually set)
  if (!amount && withdrawAmount <= minAmountBI) {
    log(
      `Skipping: Balance (${formattedAmount} sUSDe) is below minimum threshold (${minAmount})`,
    );
    return;
  }

  // 4. Execution
  log(`Requesting withdrawal for ${formattedAmount} sUSDe...`);

  try {
    const tx = await arm.connect(signer).requestBaseWithdrawal(withdrawAmount);
    await logTxDetails(tx, "requestEthenaWithdrawal");
  } catch (err) {
    log(`Error requesting withdrawal: ${err.message}`);
  }
};

// --- CONSTANTS ---
const SUSDE_ADDRESS = "0x9D39A5DE30e57443BfF2A8307A4256c8797A3497";
const SUSDE_ABI = [
  "function cooldowns(address) view returns (uint104,uint152)",
];

// --- HELPER: CORE LOGIC ---
// Fetches data for a list of addresses in PARALLEL (much faster)
const fetchUnstakerStates = async (signer, addresses) => {
  const contract = new ethers.Contract(SUSDE_ADDRESS, SUSDE_ABI, signer);
  const { timestamp: currentTimestamp } =
    await signer.provider.getBlock("latest");

  // Promise.all executes all RPC calls simultaneously
  return Promise.all(
    addresses.map(async (addr) => {
      const [cooldownEnd, underlyingAmount] = await contract.cooldowns(addr);
      const amountStr = formatUnits(underlyingAmount, 18);
      const isBalancePositive = underlyingAmount > 0;

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
        address: addr,
        rawAmount: underlyingAmount, // Keep BigNumber for calculations
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

  // Reuse the core logic
  const allStates = await fetchUnstakerStates(signer, UNSTAKERS);

  // Filter and Log
  const active = allStates.filter((s) => s.hasBalance);

  log(`Found ${active.length} active unstakers:`);
  active.forEach((u) => {
    log(` - ${u.address}: ${u.amount} sUSDe\t| Status: ${u.timeLeft}`);
  });

  return active;
};

const claimEthenaWithdrawals = async (options) => {
  const { arm, signer, unstaker } = options;

  // Determine target list: single unstaker OR all of them
  const targets = unstaker ? [unstaker] : UNSTAKERS;

  log(`Checking status for ${targets.length} address(es)...`);

  // 1. Fetch all data in parallel first (Fast)
  const states = await fetchUnstakerStates(signer, targets);

  // 2. Log status for everyone
  states.forEach((s) => {
    if (s.hasBalance && !s.isReady) {
      log(
        `Unstaker ${s.address} cooldown not completed; ending in ${s.timeLeft}`,
      );
    }
  });

  // 3. Filter who is ready to claim
  const claimable = states.filter((s) => s.isReady && s.hasBalance);

  // 4. Execute Claims
  if (claimable.length > 0) {
    log(`About to claim ${claimable.length} withdrawal requests...`);

    // Sequential execution for Transactions is safer to avoid nonce errors
    for (const item of claimable) {
      log(` - Processing claim for: ${item.address} (${item.amount} USDe)`);
      try {
        const tx = await arm.connect(signer).claimBaseWithdrawals(item.address);
        await logTxDetails(tx, `claimEthenaWithdrawal for ${item.address}`);
      } catch (err) {
        log(`Error claiming for ${item.address}: ${err.message}`);
      }
    }
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

// The list of 42 addresses
const UNSTAKERS = [
  "0x77789BB87eAdfC429440209F7d28ED55aC15f17a",
  "0x60CE563b5825Ff8ce932A2c8eCd32878639a4254",
  "0xD88011b85685de9E5c0385Ef93c0E5A75666D043",
  "0xD6F32654bAfb110A2DFbad18c8a25749c0A7f626",
  "0x9C4a2B57310Ddc479A5D7b7d68Fa1e0425D35D41",
  "0x7be23c73Ee70029Adf6a062dFbAE7B1518583630",
  "0x6B444A63967059b52A7FB8F223a03EA693a936F9",
  "0x39746c02FD20215cC6c33C2CCb49405a531F6AEa",
  "0xD0554178956c702baE69DAaceD35Bb747286bC49",
  "0x87c782917FAB4c2D4D921E767B26f82E7b2A5FD3",
  "0x9b7dB18B1da996a3BFa4a9224cA60d2a267e6065",
  "0xE671E4BD15f26609DE99ef028Fa27A5A4c839182",
  "0x84425544aB8b6c3c0Ca2a3c78A90d92089fA3a3d",
  "0x74C820df2b7D08EEB9cA9227B1aEc12D8A5C7B21",
  "0x98e7d36007f864593330C1183aba85a49aA2D3e8",
  "0x0F13DE7069020390741fbc9FFB6AA4931Ea4B28a",
  "0x9DbB3D287F6e47331758e32F981281c59606a300",
  "0xCca8EE05d84be9b19632c803633Bb9Cc879548c7",
  "0x6241882D5c39E423c040c178AB364a228C648d3C",
  "0xAA68295E2f05bb82143dF6937d99681916999Dda",
  "0x61b740C3a571237a7d978f4EE237Be15409523d2",
  "0xA39f03ba9ff8Ce1491d7Df4cAEd20a884E03b46c",
  "0xff1F36047D5D0BFbD15D5fB0adcee4F3E4743E6d",
  "0x663671666dEeD69c6a3d0F4a7b4f87Ad8b727B61",
  "0x642F99190FE78827404664Ea94931014e1c6cD7E",
  "0x0e98a4E0F840D98d54d891FC5cd1a2506E8DCF07",
  "0x47D3aeda299fFfA802E2C1099F0501F67b75a4f6",
  "0x3dBBa9614aBE1422136822e419344eDfB2A039A0",
  "0xe2B5D52C636aC568e00F31C9fa96394BfEF49d1E",
  "0xC8Fc241F85e18325f1a32688B59139e44249B64B",
  "0x2440d433AB6A32A1206463Ef75A3E3dB4CC0a5d8",
  "0xEBb379BC2f6ce49A20a14d2187B9876467994F24",
  "0xCBC12a888B037138530c76718dC77B49ae2AAb0F",
  "0xAd090F45EF9f1b748843833C1055022e88bBbE81",
  "0x5559CBF6b80dEE109149AcA01B5dE3Eac950A7ef",
  "0xc2776a7C73c41c732cF412A967703F699c75675E",
  "0xeB5C42d2B3edF5f61128bb7D36C2C7dabd24e45C",
  "0x58610F7984761217331A568e9FeBBF2F0D7cC41c",
  "0x28F1896eC1dc7342735F2D715C6f4333ff1C91a4",
  "0x3df2d3acc03B7BB618c5257A14834B1B7f3ea85B",
  "0xde02336439Bb3894f983524cD451b19FB404f76D",
  "0x38bF73Ac771bf47A403ebA754F9070Ec9FAC0F5E",
];

module.exports = {
  requestEthenaWithdrawals,
  claimEthenaWithdrawals,
  ethenaWithdrawStatus,
};
