# Share Price Inflation

Vault/lending protocols where the exchange rate between shares and underlying assets can be artificially inflated. The attacker donates tokens directly to a vault (bypassing `deposit()`), inflating `balanceOf(vault)` relative to `totalSupply`, then exploits the distorted share price to over-borrow, under-deposit, or steal from subsequent depositors. 2 incidents in 2025 with up to $41M loss (GMX).

**Severity**: Critical
**Checklist IDs**: D2, D10, FL1, FL2
**Code Characteristics**: ERC-4626 vault, share-based accounting, lending, collateral valuation

## Root Cause

The exchange rate is computed as `totalAssets / totalSupply` where `totalAssets` relies on `balanceOf(address(this))`. An attacker can inflate `totalAssets` without increasing `totalSupply` by directly transferring tokens to the vault contract. This creates a discrepancy:

1. **First-depositor attack** — attacker deposits 1 wei, donates a large amount, making 1 share worth enormous assets. Subsequent depositors receive 0 shares due to rounding.

2. **Oracle dependency on manipulable vault** — Protocol A uses Protocol B's share price as collateral valuation. Attacker donates to Protocol B's vault, inflating its share price, then over-borrows in Protocol A against the inflated collateral.

3. **Reentrancy during state transition** — callback mechanisms (position callbacks, ETH transfer fallback) execute during state updates, allowing nested operations while exchange rates are inconsistent.

## Vulnerable Code Pattern

```solidity
// VULNERABLE — exchange rate derived from manipulable balance
function exchangeRate() public view returns (uint256) {
    if (totalSupply == 0) return INITIAL_RATE;
    return underlying.balanceOf(address(this)) * SCALE / totalSupply;
    //     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ inflatable via direct transfer
}

function deposit(uint256 assets) external returns (uint256 shares) {
    shares = assets * totalSupply / underlying.balanceOf(address(this));
    // After donation: balanceOf is huge, so shares rounds to 0
    _mint(msg.sender, shares);
    underlying.transferFrom(msg.sender, address(this), assets);
}
```

### Variants

**Variant A — Direct donation to vault (classic first-depositor):**
```solidity
// Attacker:
// 1. deposit(1) → gets 1 share
// 2. token.transfer(vault, 1_000_000e18) → donates directly
// 3. exchangeRate() = 1_000_000e18 / 1 = 1_000_000e18 per share
// 4. Victim deposits 999_999e18 → gets 0 shares due to rounding
// 5. Attacker withdraws 1 share → receives 1_999_999e18
```

**Variant B — Oracle dependency on manipulable intermediate vault (ResupplyFi, ~$9.6M):**
```solidity
// ResupplyFi values collateral using crvUSD controller's share price
// Attacker: transfers crvUSD directly to controller, mints 1 wei sCrvUSD
// → inflates controller's "price per share"
// → ResupplyFi's collateral valuation skyrockets
// → attacker borrows far more reUSD than collateral is worth
function getCollateralValue(uint256 shares) public view returns (uint256) {
    uint256 pricePerShare = vault.exchangeRate();  // inflated
    return shares * pricePerShare / SCALE;
}
```

**Variant C — Reentrancy-based state manipulation (GMX, ~$41M):**
```solidity
// GMX position callback executes during state transition
// Attacker manipulates globalShortAveragePrice via reentrancy
// then mints GLP tokens at a favorable exchange rate
function gmxPositionCallback(...) external {
    // State is inconsistent during this callback
    // Attacker performs nested operations at manipulated price
}
```

## Detection Heuristic

- [ ] Does the contract derive exchange rates from `balanceOf(address(this))` divided by `totalSupply`?
- [ ] Is there a `totalSupply == 0` or very-low-supply edge case allowing extreme price-per-share?
- [ ] Can tokens be transferred directly to the vault without going through `deposit()`?
- [ ] Does any protocol use another vault's share price as collateral oracle without TWAP or bounds?
- [ ] Are there callback functions (fallback, flash loan callbacks, position callbacks) during state transitions?
- [ ] Is there a minimum deposit/share requirement to prevent 1-wei inflation?

If exchange rate uses `balanceOf` + no donation protection: **Critical**.

## Fix / Mitigation

1. **Virtual shares and virtual assets** (ERC-4626 best practice):
   ```solidity
   function _totalAssets() internal view returns (uint256) {
       return _internalBalance + 1;  // virtual asset
   }
   function _totalSupply() internal view returns (uint256) {
       return totalSupply + 1e6;     // virtual shares (dead shares)
   }
   ```

2. **Internal accounting** — track deposits via storage, not `balanceOf`:
   ```solidity
   uint256 internal _trackedBalance;
   function deposit(uint256 assets) external {
       _trackedBalance += assets;
       // Use _trackedBalance for exchange rate, not balanceOf
   }
   ```

3. **Minimum first deposit** to prevent 1-wei share manipulation:
   ```solidity
   if (totalSupply == 0) {
       require(assets >= MIN_FIRST_DEPOSIT, "too small");
       _mint(address(0xdead), DEAD_SHARES);  // burn initial shares
   }
   ```

4. **Reentrancy guards** on all state-changing functions, especially those with external callbacks.

5. **Oracle sanity bounds** — cap maximum per-block price change:
   ```solidity
   require(newPrice <= lastPrice * 110 / 100, "price jump too large");
   ```

## Proof (2025 Incidents)

| Protocol | Date | Loss | Variant | PoC |
|----------|------|------|---------|-----|
| GMX | 2025 | ~$41M | C: Reentrancy-based state manipulation via position callbacks | [DeFiHackLabs](https://github.com/SunWeb3Sec/DeFiHackLabs) |
| ResupplyFi | 2025 | ~$9.6M | B: Direct donation inflates oracle price for borrowing | [DeFiHackLabs](https://github.com/SunWeb3Sec/DeFiHackLabs) |

## Related Patterns

- [precision-rounding](./precision-rounding.md) — rounding errors in share calculation enable the inflation attack
- [flash-loan-amplification](./flash-loan-amplification.md) — flash loans provide capital for the donation
- [oracle-exploitation](./oracle-exploitation.md) — inflated share price used as oracle is oracle exploitation
