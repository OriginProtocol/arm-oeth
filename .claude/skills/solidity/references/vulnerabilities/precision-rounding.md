# Precision / Rounding

Arithmetic operations silently lose precision through integer truncation, unsafe type casts, or rounding that favors the attacker. The critical 2025 subpattern is **unsafe downcast** — `uint128(shares)` when `shares > type(uint128).max` silently truncates high bits, creating a massive discrepancy between recorded shares and actual collateral. 3 incidents, up to $120M (Balancer).

**Severity**: High
**Checklist IDs**: C24, C47, D10, FL2
**Code Characteristics**: vault, share calculation, fee computation, price scaling, integer casting

## Root Cause

Two main categories:

1. **Unsafe downcast truncation** — a function accepts `uint256` but internally casts to a smaller type (`uint128`, `uint96`, `uint64`). If the input exceeds the smaller type's max, the high bits are silently discarded. The system records the truncated value but calculates collateral/fees on the original full value.

2. **Division-before-multiplication / rounding direction** — integer division truncates toward zero. When this truncation consistently favors the attacker (e.g., they receive more shares or pay less fees), repeated operations can extract value. Amplified by flash loans that provide the capital to trigger rounding at scale.

A secondary 2025 pattern involves **transient storage slot collision** — `tstore`/`tload` slots reused across functions, allowing a user-controlled value (e.g., mint amount) to overwrite an authorization address. Covered in detail in [storage-collision](./storage-collision.md) but root cause is arithmetic: the stored value is reinterpreted as an address.

## Vulnerable Code Pattern

```solidity
// VULNERABLE — unsafe downcast truncates high bits
function collateralizedMint(
    uint256 shares,          // attacker passes type(uint128).max + 2
    address longRecipient,
    address shortRecipient
) external {
    uint128 mintedShares = uint128(shares);  // truncates to 1!
    _mint(longRecipient, longId, mintedShares);
    _mint(shortRecipient, shortId, mintedShares);
    // But collateral deposited was calculated on the full `shares` value
    // Attacker deposited collateral for 2^128+1 shares, received 1 share each
}
```

### Variants

**Variant A — Unsafe downcast enabling collateral theft (Alkimiya, ~$95.5K):**
```solidity
// uint128(type(uint128).max + 2) == 1
// Attacker mints 1 share, transfers type(uint128).max away,
// starts/ends pool, redeems short position for full collateral
uint128 mintedShares = uint128(shares);  // should use SafeCast
```

**Variant B — Division before multiplication in share calculation:**
```solidity
// VULNERABLE — truncation favors attacker
function convertToShares(uint256 assets) public view returns (uint256) {
    return assets * totalSupply / totalAssets;  // OK if multiply first
}
function convertToAssets(uint256 shares) public view returns (uint256) {
    return shares * totalAssets / totalSupply;  // potential rounding down
}
// With small totalSupply, rounding can be significant per operation
```

**Variant C — Fee calculation rounding to zero:**
```solidity
// VULNERABLE — small amounts round fee to zero
function calculateFee(uint256 amount) internal view returns (uint256) {
    return amount * feeRate / FEE_SCALE;  // if amount * feeRate < FEE_SCALE, fee = 0
}
// Attacker splits large operation into many small ones, each paying zero fee
```

## Detection Heuristic

- [ ] Are there explicit casts from `uint256` to `uint128`, `uint96`, `uint64` or smaller without overflow checks?
- [ ] Is `SafeCast` from OpenZeppelin used consistently for all downcast operations?
- [ ] Does any `mint` or `deposit` function accept `uint256` but store a narrower type?
- [ ] Does division happen before multiplication in share/price calculations?
- [ ] Does rounding consistently favor one party (attacker vs. protocol)?
- [ ] Can small amounts produce zero fees due to integer truncation?
- [ ] Are `unchecked` blocks used around narrowing casts?

If unsafe downcasts exist on user-controlled inputs: **Critical**. If rounding direction favors attacker: **High**.

## Fix / Mitigation

1. **Use SafeCast for all downcasts:**
   ```solidity
   import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
   uint128 mintedShares = SafeCast.toUint128(shares);  // reverts on overflow
   ```

2. **Validate input ranges explicitly:**
   ```solidity
   require(shares <= type(uint128).max, "shares overflow");
   ```

3. **Multiply before divide** (standard practice):
   ```solidity
   // SAFE: multiply first
   shares = (assets * totalSupply) / totalAssets;
   ```

4. **Round against the attacker** (protocol-favorable rounding):
   ```solidity
   // Round up when protocol is paying out
   shares = (assets * totalSupply + totalAssets - 1) / totalAssets;
   ```

5. **Minimum fee floor:**
   ```solidity
   uint256 fee = amount * feeRate / FEE_SCALE;
   if (fee == 0 && amount > 0) fee = 1;  // minimum 1 wei fee
   ```

## Proof (2025 Incidents)

| Protocol | Date | Loss | Variant | PoC |
|----------|------|------|---------|-----|
| Balancer V2 | 2025 | $120M | Rounding in rate calculations | [DeFiHackLabs](https://github.com/SunWeb3Sec/DeFiHackLabs) |
| Alkimiya | 2025-03 | ~$95.5K (1.14 WBTC) | A: Unsafe uint256→uint128 cast | `2025-03/Alkimiya_io_exp.sol` |
| yETH | 2025-01 | — | Rounding in yield calculation | `2025-01/yETH_exp.sol` |

## Related Patterns

- [share-price-inflation](./share-price-inflation.md) — rounding errors in share price enable inflation attacks
- [flash-loan-amplification](./flash-loan-amplification.md) — flash loans provide capital to trigger rounding at exploitable scale
- [storage-collision](./storage-collision.md) — LeverageSIR exploit is precision issue (value reinterpreted as address)
