# Slippage Protection Missing

Swap operations set `amountOutMin = 0` (no slippage protection), accepting any output amount regardless of price. Combined with deflationary tokens that distort LP reserves or flash-loan price manipulation, zero slippage allows maximum value extraction. 3 incidents in 2025, up to $442K (DCFToken).

**Severity**: High
**Checklist IDs**: MEV1, MEV2, D4
**Code Characteristics**: AMM swaps, DEX integration, custom buy/sell functions, bonding curves

## Root Cause

The swap call's minimum output parameter is set to zero or negligible, meaning the transaction succeeds regardless of how unfavorable the execution price is. This is dangerous because:

1. The protocol's own swaps can be sandwiched by MEV bots.
2. Attackers can manipulate the pool price (via deflationary burns, direct transfers, or flash loans) and then execute the swap at an extreme price.
3. Custom `buyToken()` functions accept `slippage = 0` and `expectAmount = 0`, providing no revert condition.

## Vulnerable Code Pattern

```solidity
// VULNERABLE — zero slippage protection
router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
    amountIn,
    0,           // amountOutMin = 0, accepts ANY output
    path,
    recipient,
    deadline
);
```

```solidity
// VULNERABLE — custom buy function with no minimum output enforcement
function buyToken(
    uint256 expectAmount,    // can be set to 0
    address salesman,
    uint16 slippage,         // ignored or not enforced
    address receiver
) external payable returns (uint256) {
    uint256 tokensOut = calculateFromBondingCurve(msg.value);
    // No: require(tokensOut >= expectAmount)
    _mint(receiver, tokensOut);
    return tokensOut;
}
```

### Variants

**Variant A — Deflationary burn + zero-slippage extraction (DCFToken, ~$442K):**
```solidity
// DCF token burns ~50% from LP pair on every transfer to pair
// Attacker: flash-loans 110M BUSD → buys DCF → transfers 82 DCF to pair
//           (triggers burn of pair reserves) → calls pair.swap() with distorted reserves
//           → extracts 72.6M BUSD → sells remaining DCF
// All victim contract swaps use amountOutMin = 0
```

**Variant B — Custom buyToken() with zero slippage (Pump, ~11.29 BNB):**
```solidity
// Multiple BSC tokens implement buyToken() accepting slippage = 0
// Attacker: flash-loans 100 BNB → seeds pair → adds liquidity
//           → calls buyToken{value: 20 ether}(0, address(0), 0, address(this))
//           → dumps tokens back via router
// Hits 4 tokens (TAGAIFUN, GROK, PEPE, TEST) in same transaction
```

**Variant C — Direct pair.swap() bypassing router:**
```solidity
// VULNERABLE — pair.swap() called directly without router slippage checks
pair.swap(amount0Out, amount1Out, recipient, "");
// No minimum output validation, no deadline
```

## Detection Heuristic

- [ ] Any swap call with `amountOutMin = 0` or negligible minimum output?
- [ ] Custom `buyToken()` or swap functions accepting `slippage = 0` or `expectAmount = 0`?
- [ ] `pair.swap()` called directly instead of through router?
- [ ] Token transfer function has pair-address-specific burn/tax logic altering LP reserves?
- [ ] Flash-loaned funds used to add/remove liquidity in same transaction as swaps?
- [ ] Deadline parameter set to `block.timestamp` (always passes)?

If zero-slippage swap on contract holding user funds: **High**. If combined with manipulable token mechanics: **Critical**.

## Fix / Mitigation

1. **Always set meaningful amountOutMin** — calculate from oracle or off-chain price:
   ```solidity
   uint256 expectedOut = oracle.getExpectedOutput(amountIn);
   uint256 minOut = expectedOut * (10000 - SLIPPAGE_BPS) / 10000;
   router.swap(amountIn, minOut, path, recipient, deadline);
   ```

2. **Enforce slippage in custom swap functions:**
   ```solidity
   function buyToken(uint256 minOut, ...) external payable {
       uint256 tokensOut = calculateFromBondingCurve(msg.value);
       require(tokensOut >= minOut, "slippage exceeded");
       _mint(msg.sender, tokensOut);
   }
   ```

3. **Use realistic deadlines** — not `block.timestamp`:
   ```solidity
   uint256 deadline = block.timestamp + 300; // 5 minutes
   ```

4. **Route through routers** — never call `pair.swap()` directly for user-facing operations.

5. **TWAP validation** before large swaps:
   ```solidity
   uint256 spotPrice = getSpotPrice();
   uint256 twapPrice = getTwapPrice(30 minutes);
   require(spotPrice * 100 / twapPrice > 95, "price deviated from TWAP");
   ```

## Proof (2025 Incidents)

| Protocol | Date | Loss | Variant | PoC |
|----------|------|------|---------|-----|
| DCFToken | 2025-03 | ~$442K | A: Deflationary LP burn + zero-slippage swap | `2025-03/DCFToken_exp.sol` |
| Pump (4 tokens) | 2025-03 | ~11.29 BNB | B: Custom buyToken() with zero slippage | `2025-03/Pump_exp.sol` |

## Related Patterns

- [price-manipulation](./price-manipulation.md) — manipulated price + zero slippage = maximum extraction
- [deflationary-token-bugs](./deflationary-token-bugs.md) — deflationary burns distort reserves before the zero-slippage swap
- [flash-loan-amplification](./flash-loan-amplification.md) — flash loans fund the price manipulation
