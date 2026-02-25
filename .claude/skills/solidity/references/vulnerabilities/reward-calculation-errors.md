# Reward Calculation Errors

Staking/reward contracts use flawed formulas to compute user rewards — using live pool balances instead of snapshots, not updating time/epoch checkpoints correctly, or allowing external inflation of the reward calculation basis. Attackers deposit flash-loaned amounts, manipulate pool balances, or call `claim` repeatedly. 6 incidents in 2025, up to ~$32K (SWAPPStaking).

**Severity**: Medium
**Checklist IDs**: D2, D10, FL1, C22
**Code Characteristics**: staking, reward distribution, yield farming, dividend contracts

## Root Cause

The reward formula has one or more of these flaws:

1. **Uses live pool balances** — `token.balanceOf(pair)` instead of internally tracked accounting. An attacker flash-loans tokens into the pair to inflate the reward basis.

2. **Missing checkpoint update** — `lastClaimTime` or `rewardDebt` is not updated atomically with reward distribution. The same claim can be called thousands of times in one transaction.

3. **Self-referential operations** — `buyFor(address(this))` or `deposit()` with the contract's own balance inflates dividend tracking without economic cost.

4. **Emergency withdraw without accounting reset** — `emergencyWithdraw()` returns the full deposit but doesn't adjust global counters (`totalStaked`, `rewardDebt`), breaking accounting for all other users.

## Vulnerable Code Pattern

```solidity
// VULNERABLE — reward based on live pair balance, claimable repeatedly
function extractReward(uint256 tokenId) external {
    uint256 pairBalance = token.balanceOf(lpPair);  // manipulable!
    uint256 reward = userStake[tokenId] * rewardRate / pairBalance;
    token.transfer(msg.sender, reward);
    // Missing: lastClaimTime[tokenId] = block.timestamp;
    // Can be called 2000 times in one transaction
}
```

### Variants

**Variant A — Live balance + missing checkpoint (LPMine, ~24K USDT):**
```solidity
// extractReward() uses LP pair's live token balance
// Time checkpoint not properly updated
// Attacker flash-loans USDT into pair, loops 2000 extractReward() calls
```

**Variant B — Repeated withdraw drains rewards (SorStaking, ~8 ETH):**
```solidity
// withdraw(1) pays accumulated rewards on each call
// without resetting the reward counter
// Attacker deposits, waits 14 days, calls withdraw(1) 800 times
// Each call receives the full reward allocation
function withdraw(uint256 amount) external {
    uint256 reward = calculateReward(msg.sender);
    token.transfer(msg.sender, reward);
    // Missing: rewardDebt[msg.sender] = accRewardPerShare * balance[msg.sender];
    balance[msg.sender] -= amount;
}
```

**Variant C — Self-referential dividend inflation (BankrollNetwork, ~404 WBNB):**
```solidity
// buyFor() can be called with the contract itself as customer
// Each call inflates totalDividends proportionally
function buyFor(address customer, uint256 amount) external {
    totalDividends += amount * dividendRate / totalSupply;
}
// Attacker calls buyFor(address(bankRoll), balance) 2810 times
// → massively inflates dividendsOf(attacker) → sells and withdraws
```

**Variant D — Emergency withdraw without accounting reset (SWAPPStaking, ~$32K):**
```solidity
// emergencyWithdraw() returns full deposit without adjusting global state
function emergencyWithdraw() external {
    uint256 amount = userDeposits[msg.sender];
    delete userDeposits[msg.sender];
    token.transfer(msg.sender, amount);
    // Missing: totalStaked -= amount; rewardDebt adjustment
}
// Attacker deposits the staking contract's own cToken balance
// → calls emergencyWithdraw() to extract it all
```

## Detection Heuristic

- [ ] Reward calculation uses `token.balanceOf(someAddress)` instead of internally tracked variable?
- [ ] `withdraw()` or `claim()` callable repeatedly without cooldown/checkpoint update?
- [ ] `lastClaimTime` or `rewardDebt` not updated atomically with reward distribution?
- [ ] `buyFor()` or `deposit()` callable with the contract's own address as beneficiary?
- [ ] `emergencyWithdraw()` returns full deposit without adjusting global accounting?
- [ ] No cap on number of calls to reward functions per block/transaction?
- [ ] Flash-loanable assets used as the reward calculation basis?

If repeated claim with no checkpoint: **High**. If balance-based calculation with flash-loan exposure: **Medium**.

## Fix / Mitigation

1. **Use internal accounting, not live balances:**
   ```solidity
   uint256 internal _trackedRewardBalance;
   // Update on deposit/withdraw, not via balanceOf()
   ```

2. **Update checkpoints atomically** (Synthetix/MasterChef pattern):
   ```solidity
   function claim() external {
       uint256 reward = balance[msg.sender] *
           (accRewardPerShare - rewardDebt[msg.sender]) / 1e18;
       rewardDebt[msg.sender] = accRewardPerShare; // update checkpoint
       token.transfer(msg.sender, reward);
   }
   ```

3. **Restrict self-referential operations:**
   ```solidity
   require(customer != address(this), "self-referential");
   ```

4. **Proper emergency withdraw** — zero all tracking:
   ```solidity
   function emergencyWithdraw() external {
       uint256 amount = userDeposits[msg.sender];
       totalStaked -= amount;
       delete userDeposits[msg.sender];
       delete rewardDebt[msg.sender];
       token.transfer(msg.sender, amount);
   }
   ```

## Proof (2025 Incidents)

| Protocol | Date | Loss | Variant | PoC |
|----------|------|------|---------|-----|
| LPMine | 2025-01 | ~24K USDT | A: Balance-based reward, 2000x claim loop | `2025-01/LPMine_exp.sol` |
| SorStaking | 2025-01 | ~8 ETH | B: Repeated withdraw(1) drains rewards | `2025-01/sorraStaking.sol` |
| BankrollNetwork | 2025 | ~404 WBNB | C: Self-referential buyFor() inflates dividends | [DeFiHackLabs](https://github.com/SunWeb3Sec/DeFiHackLabs) |
| SWAPPStaking | 2025 | ~$32K | D: emergencyWithdraw drains pool | [DeFiHackLabs](https://github.com/SunWeb3Sec/DeFiHackLabs) |

## Related Patterns

- [logic-flaw-state-transition](./logic-flaw-state-transition.md) — reward errors are a subtype of state transition flaws
- [flash-loan-amplification](./flash-loan-amplification.md) — flash loans inflate the balance-based reward basis
- [reentrancy](./reentrancy.md) — repeated-call drain via reentrancy achieves same effect as explicit loops
