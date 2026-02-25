# Reentrancy

External calls (ETH transfers, callback hooks) made before critical state updates allow the attacker to re-enter the vulnerable function during the external call, executing the same claim/withdrawal logic multiple times against stale state. A well-known pattern that still appears in 2025 — 3 incidents, primarily through native ETH sends and ERC-1155 callbacks.

**Severity**: High
**Checklist IDs**: F6, F9, X3, X4, D7
**Code Characteristics**: ETH transfers, callback-capable tokens, claim/withdraw functions, NFT minting

## Root Cause

The function violates the Checks-Effects-Interactions (CEI) pattern:
1. **Check** — reads a balance/reward from storage.
2. **Interaction** — sends ETH or triggers a callback (ERC-721/1155 `safeTransfer`, flash loan callback).
3. **Effect** — updates storage (zeros balance, marks as claimed).

The attacker's receiving contract re-enters during step 2, before step 3 executes. The stale storage state passes the check again, allowing repeated extraction.

## Vulnerable Code Pattern

```solidity
// VULNERABLE — state update AFTER external call
function claimReward() external {
    uint256 reward = pendingRewards[msg.sender]; // 1. CHECK: read stale state
    require(reward > 0, "nothing to claim");
    (bool ok, ) = msg.sender.call{value: reward}(""); // 2. INTERACTION: re-entrant!
    require(ok);
    pendingRewards[msg.sender] = 0; // 3. EFFECT: too late, already re-entered
}
```

### Variants

**Variant A — ETH-send reentrancy via `receive()` (StepHeroNFTs, 137.9 BNB):**
```solidity
// claimReferral() sends ETH → attacker's receive() re-enters claimReferral()
// Drains accumulated referral balances multiple times before zeroing
function claimReferral() external {
    uint256 amount = referralBalance[msg.sender];
    (bool ok,) = msg.sender.call{value: amount}("");  // re-entry point
    require(ok);
    referralBalance[msg.sender] = 0;  // update after send
}
```

**Variant B — ERC-1155 callback reentrancy:**
```solidity
// VULNERABLE — safeTransferFrom triggers onERC1155Received callback
function buyAsset(uint256 id, uint256 amount, address buyer) external payable {
    _safeTransferFrom(address(this), buyer, id, amount, "");
    // Callback here: buyer's onERC1155Received re-enters
    referralBalance[referrer] += commission;  // accounting after callback
}
```

**Variant C — Cross-function reentrancy:**
```solidity
// buyAsset() sets up referral commission
// During NFT transfer callback, attacker calls claimReferral()
// before buyAsset() finishes its accounting
// Both functions share referralBalance state
```

## Detection Heuristic

- [ ] Any function that sends ETH via `call{value:}`, `transfer()`, or `send()` before updating storage?
- [ ] Functions that invoke external callbacks (ERC-721/1155 `safeTransfer`, flash loan callbacks) before state finalization?
- [ ] `claimReward` / `withdraw` patterns where balance zeroing occurs after the transfer?
- [ ] No `nonReentrant` modifier on functions that perform external calls?
- [ ] Multiple functions sharing state where one triggers callbacks and the other reads the shared state?
- [ ] Contract receives ETH and interacts with the same protocol?

If ETH sent before state update + no reentrancy guard: **High**. If cross-function reentrancy on shared state: **Critical**.

## Fix / Mitigation

1. **Checks-Effects-Interactions** — zero the balance before the call:
   ```solidity
   function claimReward() external {
       uint256 reward = pendingRewards[msg.sender];
       require(reward > 0);
       pendingRewards[msg.sender] = 0;             // EFFECT first
       (bool ok,) = msg.sender.call{value: reward}(""); // INTERACTION last
       require(ok);
   }
   ```

2. **Reentrancy guard** (OpenZeppelin `ReentrancyGuard`):
   ```solidity
   function claimReward() external nonReentrant { ... }
   function buyAsset(...) external payable nonReentrant { ... }
   ```

3. **Pull-over-push** — credit an internal balance, let users withdraw separately:
   ```solidity
   // Instead of sending ETH in claimReward:
   claimableBalance[msg.sender] += reward;
   // Separate withdraw function with CEI
   ```

4. **Avoid raw ETH sends** — use WETH wrapping:
   ```solidity
   IWETH(weth).deposit{value: reward}();
   IWETH(weth).transfer(msg.sender, reward);
   ```

## Proof (2025 Incidents)

| Protocol | Date | Loss | Variant | PoC |
|----------|------|------|---------|-----|
| StepHeroNFTs | 2025-02 | 137.9 BNB | A: ETH-send reentrancy in claimReferral | `2025-02/StepHeroNFTs_exp.sol` |
| Unverified_35bc | 2025-02 | $6,700 | Slot-unlock callback reentrancy | `2025-02/unverified_35bc_exp.sol` |

## Related Patterns

- [logic-flaw-state-transition](./logic-flaw-state-transition.md) — repeated-call drain via reentrancy vs. explicit loop achieve same effect
- [flash-loan-amplification](./flash-loan-amplification.md) — flash loans can be combined with reentrancy for amplification
