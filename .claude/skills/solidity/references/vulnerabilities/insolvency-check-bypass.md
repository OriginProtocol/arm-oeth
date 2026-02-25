# Insolvency Check Bypass

Lending/margin protocols where the solvency validation — the check ensuring a borrower has sufficient collateral — can be circumvented. The attacker either exploits an action dispatch that skips the check for certain action types, or manipulates spot prices to settle positions at artificial values. 3 incidents in 2025, up to $1.8M (Abracadabra/MIM).

**Severity**: High
**Checklist IDs**: D1, D5, F5, F11, O1, O5
**Code Characteristics**: lending, borrowing, margin trading, multi-action dispatch (cook/execute)

## Root Cause

The protocol's solvency check — `require(collateral >= debt * ratio)` — is either:

1. **Skipped for certain action types** — multi-action `cook()` or `execute()` functions process arrays of actions. Certain action types (e.g., `ACTION_REPAY`) trigger fund outflows without the corresponding solvency check that would apply to explicit `borrow()` calls.

2. **Uses spot price vulnerable to flash manipulation** — position settlement uses a DEX spot price. The attacker opens a leveraged position, then in a separate transaction flash-loans to crash the spot price, closes the position at the manipulated price, and profits from the difference.

3. **Checks global limits instead of per-user solvency** — the protocol checks `borrowLimit >= availableBalance` (a global cap) but not whether individual borrowers are properly collateralized.

## Vulnerable Code Pattern

```solidity
// VULNERABLE — action dispatch skips solvency check for certain actions
function cook(
    uint8[] calldata actions,
    uint256[] calldata values,
    bytes[] calldata datas
) external {
    for (uint i = 0; i < actions.length; i++) {
        if (actions[i] == ACTION_REPAY) {
            // "repay" action actually triggers internal transfer logic
            (uint256 amount, address to) = abi.decode(datas[i], (uint256, address));
            _transferOut(amount, to);  // sends tokens without collateral check!
        }
    }
    // Solvency check only runs for some action combinations, not all paths
}
```

### Variants

**Variant A — cook() action bypass (Abracadabra/MIM, ~$1.8M):**
```solidity
// ACTION_REPAY misused to extract MIM without collateral
// Attacker submits cook() with ACTION_REPAY targeting 6 Cauldrons
// The "repay" action path internally triggers fund transfer
// without the solvency validation that normal borrow() would enforce
// Result: drains entire MIM balance from each Cauldron via BentoBox
```

**Variant B — Flash-loan price manipulation on position close (SharwaFinance, ~$146K):**
```solidity
// VULNERABLE — uses spot price for settlement
function decreaseLongPosition(uint256 id, address token, uint256 amount) external {
    uint256 currentPrice = getSpotPrice(token);  // manipulable via flash loan
    uint256 pnl = calculatePnL(positions[id], currentPrice);
    _settlePosition(id, pnl);  // settles at manipulated price
}
// Attacker: opens long, flash-loans WBTC to crash Uniswap V3 price,
// closes position at depressed price, repays flash loan at profit
```

**Variant C — Global limit vs. per-user solvency:**
```solidity
// VULNERABLE — checks pool limit, not user collateral ratio
function borrow(uint256 amount) external {
    require(borrowLimit >= availableBalance, "exceeds limit");
    // Missing: require(userCollateral[msg.sender] >= userDebt[msg.sender] * ratio)
    _transfer(asset, msg.sender, amount);
}
```

## Detection Heuristic

- [ ] Does the protocol have a multi-action `cook()` or `execute()` function? Are solvency checks applied after ALL action combinations?
- [ ] Can the "repay" or other seemingly benign actions trigger fund outflows?
- [ ] Does position settlement use spot DEX prices rather than oracle/TWAP?
- [ ] Is there a global borrow limit that could mask per-user under-collateralization?
- [ ] Can an attacker open and close positions with price manipulation between them?
- [ ] Are there flash-loan guards on position operations?

If multi-action dispatch with inconsistent solvency checks: **Critical**. If spot-price settlement: **High**.

## Fix / Mitigation

1. **Mandatory solvency check after every action:**
   ```solidity
   function cook(uint8[] calldata actions, ...) external {
       for (...) { _executeAction(actions[i], ...); }
       // ALWAYS check solvency at the end, regardless of action types
       require(_isSolvent(msg.sender), "insolvent");
   }
   ```

2. **Oracle-based settlement pricing:**
   ```solidity
   uint256 price = chainlinkOracle.latestAnswer();
   require(price > 0 && block.timestamp - updatedAt < STALENESS_THRESHOLD);
   ```

3. **Per-user collateral validation:**
   ```solidity
   require(getCollateralValue(msg.sender) >= getDebtValue(msg.sender) * RATIO / 1e18);
   ```

4. **Position maturity requirements** — prevent same-block manipulation:
   ```solidity
   require(block.number > positions[id].openBlock + MIN_MATURITY);
   ```

5. **Price deviation checks before settlement:**
   ```solidity
   uint256 spotPrice = getSpotPrice(token);
   uint256 oraclePrice = getOraclePrice(token);
   require(spotPrice * 100 / oraclePrice > 95, "price deviation too high");
   ```

## Proof (2025 Incidents)

| Protocol | Date | Loss | Variant | PoC |
|----------|------|------|---------|-----|
| Abracadabra (MIM/Spell) | 2025-01 | ~$1.8M | A: cook() ACTION_REPAY bypass | `2025-01/Abracadabra_exp.sol` |
| SharwaFinance | 2025 | ~$146K | B: Flash-loan price manipulation on close | [DeFiHackLabs](https://github.com/SunWeb3Sec/DeFiHackLabs) |

## Related Patterns

- [logic-flaw-state-transition](./logic-flaw-state-transition.md) — cook() action bypass is a state machine flaw
- [oracle-exploitation](./oracle-exploitation.md) — spot price settlement is oracle exploitation
- [flash-loan-amplification](./flash-loan-amplification.md) — flash loans enable the price manipulation
