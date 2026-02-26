# Deflationary Token Bugs

Tokens with transfer-time burn/tax mechanics cause the actual amount received to differ from the amount sent. When DEX pairs or integrating protocols assume `amountIn == amountReceived`, the discrepancy creates exploitable price distortions. Attackers pump pair-balance-dependent prices by looping buy/sell cycles, each cycle burning tokens from LP reserves and inflating the token's apparent value. 4 incidents in 2025, up to ~590K USDT (IPC).

**Severity**: Medium
**Checklist IDs**: D8, D2, C27
**Code Characteristics**: fee-on-transfer tokens, deflationary tokens, LP pair integrations

## Root Cause

The token's `_transfer()` function includes special logic when the `to` or `from` address is an LP pair:

1. **Burns from the pair address** during transfers — reducing the pair's token reserve and inflating the token's price per the AMM's constant-product formula.
2. **Applies a transfer tax** — the receiver gets less than sent, but the accounting assumes the full amount arrived.

When a protocol deposits or swaps these tokens using the `amount` parameter instead of measuring `balanceAfter - balanceBefore`, the difference accumulates as exploitable value.

## Vulnerable Code Pattern

```solidity
// VULNERABLE TOKEN — burns tokens from LP pair on transfer
function _transfer(address from, address to, uint256 amount) internal override {
    if (to == pancakePair) {
        uint256 burnAmount = amount / 2;
        _burn(pancakePair, burnAmount);  // destroys LP reserves!
        super._transfer(from, to, amount - burnAmount);
    } else {
        super._transfer(from, to, amount);
    }
}
```

```solidity
// VULNERABLE INTEGRATION — uses amount parameter, not actual received
function deposit(uint256 amount) external {
    token.transferFrom(msg.sender, address(this), amount);
    shares[msg.sender] += amount;  // should use actual received amount
    // If token has 10% tax, user deposited 90% but credited 100%
}
```

### Variants

**Variant A — LP-pair burn on transfer (IPC, ~590K USDT):**
```solidity
// Every sell burns tokens from the pair
// Attacker loops 16 times: buy token → sell token (pair shrinks from burn)
// → buy again at lower price → repeat
// Each cycle extracts more USDT than the previous
// because pair's token reserve keeps shrinking
```

**Variant B — Skim/sync reserve manipulation (WETC, ~101K USD):**
```solidity
// Token has transfer tax. Attacker:
// 1. Flash-loans large amount
// 2. Transfers tokens directly to LP pair
// 3. Calls skim() to extract excess
// 4. Calls sync() to reset reserves to inflated amounts
// 5. Swaps at manipulated price
```

**Variant C — Flash-loan amplified deflationary swap (WXC, ~37.5 WBNB):**
```solidity
// Attacker takes flash loan, triggers swap through LP pair,
// uses pancakeCall callback to deposit WBNB, then swaps accumulated
// deflationary tokens back using swapExactTokensForTokensSupportingFeeOnTransferTokens
// Imbalance between expected and received (after tax) creates arbitrage profit
```

## Detection Heuristic

- [ ] Token `_transfer()` contains special logic when `to` or `from` is an LP pair address?
- [ ] Token burns from addresses other than `from` during transfer (especially burning from LP pair)?
- [ ] Protocol uses `amount` parameter instead of `balanceAfter - balanceBefore` for accounting?
- [ ] LP pair `skim()` and `sync()` called in sequence (reserve manipulation)?
- [ ] Repeated swap loops (buy/sell cycles) in the same transaction?
- [ ] `swapExactTokensForTokensSupportingFeeOnTransferTokens` usage — are ALL integration points aware?

If token burns from pair + protocol assumes full amount received: **High**. Protocol-side accounting mismatch alone: **Medium**.

## Fix / Mitigation

1. **Measure actual received amounts:**
   ```solidity
   uint256 balBefore = token.balanceOf(address(this));
   token.transferFrom(msg.sender, address(this), amount);
   uint256 received = token.balanceOf(address(this)) - balBefore;
   shares[msg.sender] += received;  // credit actual amount
   ```

2. **Do not burn from third-party addresses** in token contracts:
   ```solidity
   // SAFE: burn from sender only
   _burn(from, burnAmount);
   super._transfer(from, to, amount - burnAmount);
   ```

3. **Remove pair-address-specific transfer logic** — apply uniform tax regardless of recipient.

4. **Document token compatibility** — explicitly declare whether fee-on-transfer tokens are supported:
   ```solidity
   /// @notice This vault does NOT support fee-on-transfer tokens
   ```

## Proof (2025 Incidents)

| Protocol | Date | Loss | Variant | PoC |
|----------|------|------|---------|-----|
| IPC | 2025-01 | ~590K USDT | A: LP-pair burn on sell, 16 iterative swaps | `2025-01/IPC_exp.sol` |
| WXC Token | 2025 | ~37.5 WBNB | C: Flash-loan + callback deflationary swap | [DeFiHackLabs](https://github.com/SunWeb3Sec/DeFiHackLabs) |
| WETC Token | 2025 | ~101K USD | B: Transfer tax + skim/sync manipulation | [DeFiHackLabs](https://github.com/SunWeb3Sec/DeFiHackLabs) |

## Related Patterns

- [price-manipulation](./price-manipulation.md) — deflationary burns are a price manipulation mechanism
- [slippage-protection-missing](./slippage-protection-missing.md) — deflationary token + zero slippage = maximum extraction
- [flash-loan-amplification](./flash-loan-amplification.md) — flash loans amplify the iterative swap attack
