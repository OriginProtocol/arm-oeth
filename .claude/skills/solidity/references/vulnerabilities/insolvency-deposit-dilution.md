# Insolvency Deposit Dilution

A vault or share-based system allows deposits during insolvency. When `totalAssets()` floors at a minimum value (or the vault is underwater), `convertToShares()` returns an outsized number of shares for a small deposit. The attacker acquires a dominant share position cheaply, dilutes pending withdrawal claims to near-zero, and captures the freed assets when those claims settle. The attacker's profit comes from existing LP principal — direct theft of funds.

**Severity**: Critical
**Checklist IDs**: D14, D15, D16, FL1
**Code Characteristics**: ERC-4626 vault, share-based accounting, withdrawal queue, async redemption

## Root Cause

Three interacting components:

1. **`totalAssets()` floor during insolvency** — when assets fall below outstanding obligations (slashing, depeg, market loss), `totalAssets()` returns a floored minimum (e.g., `MIN_TOTAL_SUPPLY = 1e12`) rather than a true (possibly negative) net value. This is typically a safety mechanism to prevent division by zero.

2. **No deposit guard during insolvency** — `deposit()` / `mint()` remains callable when the vault is insolvent. Share pricing uses the floored `totalAssets()`, so `shares = deposit * totalSupply / totalAssets()` produces an enormous number of shares for a small deposit. Example: with `totalAssets() = 1e12` and `totalSupply = 1e12` (only dead shares), depositing 20 WETH yields 20e18 shares — dominating the vault.

3. **Claim payout diverges from claim accounting** — the withdrawal queue pays `min(request.assets, convertToAssets(request.shares))`, which is near-zero after dilution. But the queue accounting clears the full `request.assets` from `outstandingWithdrawals` / `withdrawsClaimed`. This frees the locked assets, which now belong proportionally to the attacker's dominant share position.

The attacker does not need to cause the insolvency — they wait for or observe a natural event (stETH slashing, sUSDe depeg, lending market loss) and then act.

## Vulnerable Code Pattern

```solidity
// VULNERABLE — deposit callable during insolvency, no guard
uint256 constant MIN_TOTAL_SUPPLY = 1e12;

function totalAssets() public view returns (uint256) {
    uint256 assets = _liquidityBalance() + _externalWithdrawQueue();
    uint256 outstanding = outstandingWithdrawals;
    // Floor: when assets < outstanding, return minimum
    if (assets < outstanding) return MIN_TOTAL_SUPPLY;
    return assets - outstanding + MIN_TOTAL_SUPPLY;
}

function _deposit(uint256 assets, address receiver) internal returns (uint256 shares) {
    shares = convertToShares(assets);  // No insolvency check!
    // During insolvency: shares = assets * totalSupply / totalAssets()
    //                          = 20e18 * 1e12 / 1e12 = 20e18
    _mint(receiver, shares);
    token.transferFrom(msg.sender, address(this), assets);
}

function claimRedeem(uint256 requestId) external returns (uint256 assets) {
    Request memory request = requests[requestId];
    // Payout: min of requested amount and current share value
    assets = min(request.assets, convertToAssets(request.shares));
    // During dilution: convertToAssets(shares) ≈ 0
    // So LP gets ~0...

    // But accounting clears the FULL requested amount:
    withdrawsClaimed += request.assets;  // Frees the full obligation!
    token.transfer(msg.sender, assets);  // Sends ~0
}
```

### Variants

**Variant A — Floor-based dilution with withdrawal queue (ARM protocol):**
```solidity
// Insolvency: assets=80, outstanding=100, totalAssets()=1e12 (floored)
// totalSupply=1e12 (only dead shares, LP burned via requestRedeem)
// Attacker deposits 20 WETH:
//   shares = 20e18 * 1e12 / 1e12 = 20e18
// LP claims:
//   convertToAssets(100e18) = 100e18 * 1e12 / (20e18 + 1e12) ≈ 5e12
//   LP receives 0.000005 WETH (effectively zero)
//   withdrawsClaimed += 100e18 (clears full 100 WETH obligation)
// Attacker redeems: gets ~92 WETH after fees. Profit: ~72 WETH.
```

**Variant B — Zero-totalAssets with donation recovery:**
```solidity
// Vault totalAssets() returns 0 during insolvency (no floor)
// totalSupply > 0 (existing shares not burned)
// deposit() reverts on division-by-zero... BUT
// attacker donates 1 wei to make totalAssets() = 1
// Then deposits: shares = deposit * totalSupply / 1 = enormous
// Same dilution outcome
```

**Variant C — Multi-LP amplification:**
```solidity
// Multiple LPs with pending claims + insolvency
// With 50e18 shares still in circulation:
//   totalAssets = 1e12 (floor)
//   attacker deposits 15 WETH
//   shares = 15e18 * 50e18 / 1e12 = 750e24 (dominates 50e18 existing)
// ALL pending LP claims diluted to near-zero
// Attacker captures freed assets from multiple victims
```

## Detection Heuristic

- [ ] Does the vault/system have share-based accounting (ERC-4626 or similar)?
- [ ] Does `totalAssets()` have a floor or minimum value during insolvency?
- [ ] Is `deposit()` / `mint()` callable when the system is insolvent (assets < obligations)?
- [ ] During insolvency, does `convertToShares()` return outsized shares for small deposits?
- [ ] Does the withdrawal queue / claim function pay `min(requested, convertToAssets(shares))` but clear the full `requested` amount from accounting?
- [ ] Can `totalSupply` reach a state where only dead/minimum shares remain (all LP shares burned via redeem requests)?
- [ ] Is there any external event (slashing, depeg, market loss) that could make the system insolvent?

If deposit is callable during insolvency AND claim accounting diverges from claim payout: **Critical** — direct theft of LP principal. If deposit is callable but no withdrawal queue exists (just proportional withdrawal): **Medium** — dilution without queue amplification.

## Fix / Mitigation

1. **Block deposits during insolvency:**
   ```solidity
   function _deposit(uint256 assets, address receiver) internal returns (uint256 shares) {
       require(
           _availableAssets() >= 0 || totalAssets() > MIN_TOTAL_SUPPLY,
           "deposits disabled during insolvency"
       );
       shares = convertToShares(assets);
       _mint(receiver, shares);
       token.transferFrom(msg.sender, address(this), assets);
   }
   ```

2. **Use fair share pricing during insolvency** — price shares based on actual net assets, not the floor:
   ```solidity
   function convertToShares(uint256 assets) public view returns (uint256) {
       uint256 ta = totalAssets();
       uint256 ts = totalSupply();
       if (ta <= MIN_TOTAL_SUPPLY && _isInsolvent()) {
           // Price shares at full asset value, not floor
           ta = _grossAssets();  // total assets without floor
       }
       return assets * ts / ta;
   }
   ```

3. **Cap maximum share dilution** — limit how many shares a single deposit can create relative to existing supply:
   ```solidity
   uint256 maxNewShares = totalSupply() * MAX_DILUTION_BPS / 10000;
   require(shares <= maxNewShares, "excessive dilution");
   ```

4. **Align claim payout with claim accounting** — only clear the amount actually paid:
   ```solidity
   function claimRedeem(uint256 requestId) external returns (uint256 assets) {
       Request memory request = requests[requestId];
       assets = min(request.assets, convertToAssets(request.shares));
       withdrawsClaimed += assets;  // Clear only what was paid, not full request
       token.transfer(msg.sender, assets);
   }
   ```
   Note: this changes withdrawal queue semantics and may have other implications.

5. **Pause mechanism** — automatically pause deposits when insolvency is detected:
   ```solidity
   modifier whenSolvent() {
       require(totalAssets() > outstandingWithdrawals + MIN_TOTAL_SUPPLY, "insolvent");
       _;
   }
   ```

## Proof (2025 Incidents)

| Protocol | Date | Loss | Variant | PoC |
|----------|------|------|---------|-----|
| ARM Protocol (EthenaARM) | 2025 | Up to 80%+ of LP principal | A: Floor-based dilution with withdrawal queue | Identified during security review |

## Key Insight — Why This Is Missed

This vulnerability requires **adversarial state modeling** — analyzing what happens when the system enters an extreme but realistic state (insolvency), and then checking whether permissionless entry points (deposit) become exploitable in that state. Auditors who only model normal-state interactions miss it because:

- Insolvency is a "shouldn't happen" state that feels unlikely
- The `totalAssets()` floor looks like a safety mechanism, not an attack surface
- The `claimRedeem` function looks correct in isolation — it pays the minimum of two values
- The exploit requires understanding how queue accounting (clearing `request.assets`) and share dilution interact across multiple function calls

## Related Patterns

- [share-price-inflation](./share-price-inflation.md) — both involve manipulating share pricing, but share-price-inflation uses donation in normal state; this uses natural insolvency
- [insolvency-check-bypass](./insolvency-check-bypass.md) — related concept but that pattern is about lending collateral checks, not vault deposit dilution
- [logic-flaw-state-transition](./logic-flaw-state-transition.md) — the claim payout/accounting divergence is a state transition flaw
- [precision-rounding](./precision-rounding.md) — extreme rounding (shares → 0 assets) is the mechanism that makes dilution profitable
