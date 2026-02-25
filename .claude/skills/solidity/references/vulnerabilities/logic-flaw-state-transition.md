# Logic Flaw / State Transition

The contract's state machine allows an operation to be repeated when it should be one-time, allows withdrawal without properly invalidating the position, or triggers double-counting via self-interaction. Tied with access control as the most frequent 2025 pattern (19 incidents), and responsible for the single largest loss (~$104M Hegic).

**Severity**: Critical
**Checklist IDs**: F6, F11, F12, C22, C23, D2
**Code Characteristics**: withdrawal queue, claim/redeem flows, staking, NFT transfers with rewards

## Root Cause

A state transition (withdraw, claim, transfer) does not properly invalidate the preconditions for a subsequent identical transition. Three main failure modes:

1. **Missing state invalidation** — a withdrawal function reads a balance/amount but never zeros it out, burns the position, or deletes the record. The same withdrawal can be called repeatedly.

2. **Self-transfer double-counting** — a transfer function distributes rewards to both `from` and `to`. When `from == to`, the same account receives double rewards per transfer, and the operation can be looped.

3. **Balance-based reward calculation** — rewards are computed from live pool/pair balances rather than time-weighted accumulators. An attacker inflates the balance (flash loan) or calls claim repeatedly (no checkpoint update).

## Vulnerable Code Pattern

```solidity
// VULNERABLE — withdraw does not invalidate the position
function withdrawWithoutHedge(uint256 trancheID) external returns (uint256 amount) {
    Tranche storage t = tranches[trancheID];
    amount = t.amount;                        // reads the amount
    token.transfer(msg.sender, amount);        // sends funds
    // BUG: does not set t.amount = 0 or delete the tranche
    // Can be called 100+ times for the same trancheID
}
```

### Variants

**Variant A — Repeated withdrawal (Hegic, ~$104M):**
```solidity
// Called 100 times in Tx1, 331 times in Tx2 for the same tranche
function withdrawWithoutHedge(uint256 trancheID) external returns (uint256) {
    // ... calculates amount from tranche ...
    token.transfer(msg.sender, amount);
    // Missing: tranches[trancheID].amount = 0;
}
```

**Variant B — Self-transfer double reward (IdolsNFT, 97 stETH):**
```solidity
// VULNERABLE — from == to triggers double reward
function _transfer(address from, address to, uint256 tokenId) internal {
    _claimRewards(from);   // rewards for sender
    _claimRewards(to);     // rewards for receiver — same address!
    // Looped 2000 times via safeTransferFrom(self, self, tokenId)
}
```

**Variant C — Balance-based reward, no checkpoint (LPMine, 24K USDT):**
```solidity
// VULNERABLE — reward from live balance, no time guard
function extractReward(uint256 tokenId) external {
    uint256 pairBalance = token.balanceOf(lpPair);  // manipulable
    uint256 reward = userStake[tokenId] * rewardRate / pairBalance;
    token.transfer(msg.sender, reward);
    // Missing: lastClaimTime[tokenId] = block.timestamp;
    // Called 2000 times in one transaction
}
```

## Detection Heuristic

- [ ] Does a withdrawal/claim function read a balance but NOT set it to zero or delete the record afterward?
- [ ] Can the same position ID / tranche ID be used in multiple calls?
- [ ] Does `_transfer()` distribute rewards to both `from` and `to` without checking `from != to`?
- [ ] Is reward calculation based on current pool/pair token balance rather than a snapshot or accumulator?
- [ ] Can a claim/withdraw function be called in a loop within a single transaction?
- [ ] Is there a missing reentrancy guard on withdrawal functions?

If a withdrawal function does not invalidate the position: **Critical** — repeatable drain in a single transaction.

## Fix / Mitigation

1. **Burn-on-withdraw** — always invalidate before transfer (CEI pattern):
   ```solidity
   function withdraw(uint256 trancheID) external {
       uint256 amount = tranches[trancheID].amount;
       require(amount > 0, "already withdrawn");
       delete tranches[trancheID];                // effect FIRST
       token.transfer(msg.sender, amount);          // interaction LAST
   }
   ```

2. **Disallow self-transfers in reward logic:**
   ```solidity
   require(from != to, "self-transfer");
   ```

3. **Use accumulator-based reward tracking** (Synthetix StakingRewards / MasterChef pattern):
   ```solidity
   rewardPerTokenStored += (reward * 1e18) / totalStaked;
   rewards[user] = balance[user] * (rewardPerTokenStored - userRewardPerTokenPaid[user]) / 1e18;
   ```

4. **One-claim-per-epoch** with checkpoint:
   ```solidity
   require(block.timestamp > lastClaimTime[user] + CLAIM_COOLDOWN);
   lastClaimTime[user] = block.timestamp;
   ```

## Proof (2025 Incidents)

| Protocol | Date | Loss | Variant | PoC |
|----------|------|------|---------|-----|
| HegicOptions | 2025-02 | ~$104M | A: Repeated withdraw, no invalidation | `2025-02/HegicOptions_exp.sol` |
| IdolsNFT | 2025-01 | 97 stETH | B: Self-transfer double reward | `2025-01/IdolsNFT_exp.sol` |
| LPMine | 2025-01 | 24K USDT | C: Balance-based reward, 2000x loop | `2025-01/LPMine_exp.sol` |
| SorStaking | 2025-01 | ~8 ETH | Repeated withdraw(1) drains rewards | `2025-01/sorraStaking.sol` |
| Mosca | 2025-01 | 19K | Flash loan + exit/join loop | `2025-01/Mosca_exp.sol` |
| Abracadabra | 2025-01 | $1.8M | cook() action bypass | `2025-01/Abracadabra_exp.sol` |
| FPC | 2025-02 | — | State transition flaw | `2025-02/FPC_exp.sol` |

*19 total incidents in 2025 — table shows representative subset with available PoCs.*

## Related Patterns

- [reward-calculation-errors](./reward-calculation-errors.md) — Variant C overlaps heavily; reward errors are a subtype of logic flaws
- [flash-loan-amplification](./flash-loan-amplification.md) — flash loans amplify balance-based reward exploits
- [reentrancy](./reentrancy.md) — repeated-call drain via reentrancy vs. explicit loop achieve the same effect
- [insolvency-check-bypass](./insolvency-check-bypass.md) — Abracadabra cook() bypass is both logic flaw and insolvency bypass
