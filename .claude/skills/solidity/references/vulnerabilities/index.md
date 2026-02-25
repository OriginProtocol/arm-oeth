# Vulnerability Pattern Database

Pattern-based vulnerability database distilled from 95+ real-world DeFi exploits (2025). Each file documents a generalized attack pattern with detection heuristics, vulnerable code examples, and proof from actual incidents.

**How to use this index:**
1. Identify the code's characteristics (vault, AMM, oracle-consumer, etc.)
2. Match against the Code Characteristic table below to find relevant patterns
3. Load only the matching pattern files (keep to 3-5 patterns per review)
4. Walk each pattern's detection heuristic checklist against the code under review

**Context budget:** index (~200 lines) + 3-5 patterns (~450-750 lines) = ~650-950 lines.

---

## Code Characteristic → Pattern Lookup

Primary lookup table. Match the code under review to its characteristics, then load the listed patterns.

| Code Characteristic | Load These Patterns |
|---------------------|-------------------|
| ERC-4626 vault / share-based | [share-price-inflation], [precision-rounding], [flash-loan-amplification] |
| AMM / swap / DEX | [price-manipulation], [flash-loan-amplification], [slippage-protection-missing], [reentrancy] |
| Lending / borrowing | [oracle-exploitation], [insolvency-check-bypass], [flash-loan-amplification], [precision-rounding] |
| Withdrawal queue / async redemption | [logic-flaw-state-transition], [phantom-consumption], [reentrancy], [access-control-missing] |
| Oracle consumer | [oracle-exploitation], [price-manipulation], [flash-loan-amplification] |
| Proxy / upgradeable | [storage-collision], [access-control-missing] |
| Accepts arbitrary calldata | [arbitrary-calldata], [access-control-missing] |
| Fee-on-transfer / deflationary tokens | [deflationary-token-bugs], [precision-rounding] |
| Staking / reward distribution | [reward-calculation-errors], [precision-rounding], [flash-loan-amplification] |
| Signature-gated operations | [signature-validation], [access-control-missing] |
| Holds approvals for users | [arbitrary-calldata], [access-control-missing] |
| External call to user-supplied address | [phantom-consumption], [reentrancy], [arbitrary-calldata] |
| Reads state from contract A, calls contract B | [phantom-consumption] |
| Native ETH handling | [reentrancy], [slippage-protection-missing] |
| Governance / voting | [flash-loan-amplification], [access-control-missing] |

### ARM-Specific Mapping

For ARM contracts (vault + AMM + withdrawal queue + proxy + oracle-consumer), always load:
- [access-control-missing] — proxy initialization, operator functions
- [logic-flaw-state-transition] — withdrawal queue state machine, claim/redeem flows
- [precision-rounding] — share price calculation, fee computation, price scaling
- [price-manipulation] — dual pricing, cross-price, trade rate manipulation
- [share-price-inflation] — first depositor, donation attacks on LP shares

---

## Pattern Summary

| Pattern | Severity | 2025 Incidents | Largest Loss | File |
|---------|----------|---------------|-------------|------|
| [Access Control Missing](./access-control-missing.md) | Critical | 19 | $12M | `access-control-missing.md` |
| [Logic Flaw / State Transition](./logic-flaw-state-transition.md) | Critical | 19 | ~$104M | `logic-flaw-state-transition.md` |
| [Price Manipulation](./price-manipulation.md) | High | 14 | $2M | `price-manipulation.md` |
| [Precision / Rounding](./precision-rounding.md) | High | 3 | $120M | `precision-rounding.md` |
| [Share Price Inflation](./share-price-inflation.md) | Critical | 2 | $41M | `share-price-inflation.md` |
| [Oracle Exploitation](./oracle-exploitation.md) | High | 4 | $1M | `oracle-exploitation.md` |
| [Arbitrary Calldata](./arbitrary-calldata.md) | Critical | 4 | $4.5M | `arbitrary-calldata.md` |
| [Insolvency Check Bypass](./insolvency-check-bypass.md) | High | 3 | $1.8M | `insolvency-check-bypass.md` |
| [Reentrancy](./reentrancy.md) | High | 3 | 137.9 BNB | `reentrancy.md` |
| [Deflationary Token Bugs](./deflationary-token-bugs.md) | Medium | 4 | ~590k USDT | `deflationary-token-bugs.md` |
| [Flash Loan Amplification](./flash-loan-amplification.md) | High | cross-cutting | — | `flash-loan-amplification.md` |
| [Phantom Consumption](./phantom-consumption.md) | Critical | 1 | Variable | `phantom-consumption.md` |
| [Reward Calculation Errors](./reward-calculation-errors.md) | Medium | 6 | $32k | `reward-calculation-errors.md` |
| [Slippage Protection Missing](./slippage-protection-missing.md) | High | 3 | $442k | `slippage-protection-missing.md` |
| [Signature Validation](./signature-validation.md) | High | 1 | $50k | `signature-validation.md` |
| [Storage Collision](./storage-collision.md) | Critical | 1 | $353.8k | `storage-collision.md` |

---

## Cross-Reference: Checklist IDs

Maps security-checklist.md IDs to relevant vulnerability patterns.

| Checklist IDs | Pattern |
|--------------|---------|
| F6, F9, X3, X4 | [reentrancy] |
| F9, F16, F17 | [access-control-missing] |
| D3, D4, D5, O1-O7 | [oracle-exploitation], [price-manipulation] |
| FL1, FL2, FL3, FL5 | [flash-loan-amplification], [share-price-inflation] |
| MEV1, MEV2 | [slippage-protection-missing] |
| C24, C47, D10 | [precision-rounding] |
| D2, FL2 | [share-price-inflation] |
| D8 | [deflationary-token-bugs] |
| D11 | [arbitrary-calldata] |
| D12, D13, X9, X10, X11 | [phantom-consumption] |
| SIG1-SIG7, C10, C11 | [signature-validation] |
| C7 | [storage-collision] |

---

## Adding New Patterns

1. Create `pattern-name.md` following the template below
2. Add entry to Pattern Summary table above
3. Add code characteristics to the lookup table
4. Cross-reference with security-checklist.md IDs

### Pattern File Template

```markdown
# {Pattern Name}

{Summary paragraph: what, why dangerous, typical impact.}

**Severity**: Critical / High / Medium
**Checklist IDs**: F9, D3, etc. (from security-checklist.md)
**Code Characteristics**: vault, AMM, oracle-consumer, etc.

## Root Cause
{2-3 paragraphs, generalized.}

## Vulnerable Code Pattern
` ``solidity
// VULNERABLE — {label}
` ``

### Variants
{2-3 code variations of the same root pattern}

## Detection Heuristic
- [ ] Condition 1
- [ ] Condition 2
If all met: {Severity}. If partial: investigate further.

## Fix / Mitigation
1. {Fix with code example}

## Proof (2025 Incidents)
| Protocol | Date | Loss | Variant | PoC |
|----------|------|------|---------|-----|

## Related Patterns
- [pattern-name](./pattern-name.md) — relationship
```

---

## Coverage Notes

**Excluded from database** (~7 incidents): rug pulls (trust/social issue, not code vulnerability), phishing/social engineering, weak randomness (niche, not DeFi-specific). These are operational/trust failures, not auditable code patterns.

**Cross-cutting pattern**: [flash-loan-amplification] is not a standalone vulnerability but an amplifier. It appears alongside price manipulation, share inflation, oracle exploitation, and rounding errors. Always check it when any of those patterns are flagged.
