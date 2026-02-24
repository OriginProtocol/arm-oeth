# Vulnerability Database Index

Incident-based vulnerability database for the scanner agent. Each entry documents a real-world exploit with the vulnerable pattern, detection heuristic, and mitigation.

**How to use this index:**
1. Classify the code's characteristics (vault, AMM, bridge, etc.)
2. Match against the category table below to find relevant vulnerability types
3. Load only the incident files matching those categories
4. Compare each incident's detection heuristic against the code under review

**Adding new incidents:** Create a file named `YYYY-MM-DD-protocol.md` in this directory following the template at the bottom of this file, then add it to both tables below.

---

## By Category

| Category | Incidents | Key Detection Patterns |
|----------|-----------|----------------------|
| Reentrancy | the-dao, cream-finance, curve-vyper | State modified after external call; callback-capable tokens (ERC-777, ERC-4626); read-only reentrancy via view functions |
| Flash Loans | bzx, euler-finance, harvest-finance | Same-block balance manipulation; donation attacks; share price manipulation via direct transfer |
| Oracle Manipulation | mango-markets | Single-block price reads; spot price as oracle; self-referencing price feeds |
| Access Control | parity-multisig, ronin-bridge, wormhole | Missing modifiers on state-changing functions; uninitialized ownership; proxy initialization gaps |
| Delegatecall | parity-wallet-kill | Delegatecall to user-controlled or destroyable address; library with selfdestruct |
| Vault Inflation | euler-finance | First depositor attack; totalAssets manipulable by direct transfer; no dead shares/minimum deposit |
| Bridge / Cross-chain | wormhole, nomad-bridge | Signature verification bypass; merkle proof validation; trusted relayer compromise |
| Governance | beanstalk | Flash loan + governance voting; same-block proposal + vote; no vote lock period |
| Precision / Rounding | (various — check in context) | Division before multiplication; rounding direction favoring attacker; dust amount exploitation |
| Frontrunning / MEV | (various — check in context) | Missing slippage protection; no deadline parameter; sandwich-vulnerable swaps |

## Chronological

| Date | Protocol | Category | Amount Lost | File |
|------|----------|----------|-------------|------|
| 2016-06-17 | The DAO | Reentrancy | $60M | `2016-06-17-the-dao.md` |
| 2017-07-19 | Parity Multisig | Access Control | $31M | `2017-07-19-parity-multisig.md` |
| 2017-11-06 | Parity Wallet | Delegatecall | $280M (frozen) | `2017-11-06-parity-wallet-kill.md` |
| 2020-02-15 | bZx | Flash Loan | $350K | `2020-02-15-bzx.md` |
| 2020-10-26 | Harvest Finance | Flash Loan / Oracle | $34M | `2020-10-26-harvest-finance.md` |
| 2021-10-27 | Cream Finance | Reentrancy | $130M | `2021-10-27-cream-finance.md` |
| 2022-02-02 | Wormhole | Access Control / Bridge | $326M | `2022-02-02-wormhole.md` |
| 2022-03-23 | Ronin Bridge | Access Control | $624M | `2022-03-23-ronin-bridge.md` |
| 2022-04-17 | Beanstalk | Governance | $182M | `2022-04-17-beanstalk.md` |
| 2022-08-01 | Nomad Bridge | Bridge / Merkle | $190M | `2022-08-01-nomad-bridge.md` |
| 2022-10-11 | Mango Markets | Oracle Manipulation | $117M | `2022-10-11-mango-markets.md` |
| 2023-03-13 | Euler Finance | Flash Loan / Vault | $197M | `2023-03-13-euler-finance.md` |
| 2023-07-30 | Curve / Vyper | Reentrancy | $70M | `2023-07-30-curve-vyper.md` |

---

## Incident File Template

Use this template when adding new incidents. Save as `YYYY-MM-DD-protocol.md` in this directory.

```markdown
---
date: YYYY-MM-DD
protocol: Protocol Name
chain: Ethereum / Arbitrum / etc.
amount_lost: $XXM
category: Primary Category / Secondary Category
severity: Critical
recovered: Yes / No / Partial ($XM)
---

# Protocol Name (Month Year)

## Summary
One paragraph: what happened, who was affected, immediate impact.

## Root Cause
Technical explanation of the vulnerability. Focus on the specific code pattern
that was exploitable, not the full attack transaction sequence.

## Vulnerable Code Pattern
```solidity
// Simplified, generalized pattern showing the vulnerability
// Not the actual protocol code — a pattern others can match against
function vulnerableFunction(uint256 amount) external {
    // Explain what's wrong with inline comments
}
` ` `

## Detection Heuristic
What to look for in code to spot this pattern:
- [ ] Heuristic check 1
- [ ] Heuristic check 2
- [ ] Heuristic check 3
- [ ] Heuristic check 4

## Fix / Mitigation
How to prevent this vulnerability:
- Mitigation 1 (with code example if helpful)
- Mitigation 2
- Mitigation 3

## References
- [Post-mortem or analysis link]
- [Audit report if available]
- [Transaction hash if public]
```

---

## Category → Code Characteristic Mapping

Use this mapping to determine which categories to check for a given codebase:

| Code Characteristic | Check These Categories |
|--------------------|----------------------|
| ERC-4626 vault / share-based | Vault Inflation, Flash Loans, Precision/Rounding |
| AMM / swap / DEX | Flash Loans, Oracle Manipulation, Frontrunning/MEV, Reentrancy |
| Lending / borrowing | Flash Loans, Oracle Manipulation, Reentrancy, Precision/Rounding |
| Withdrawal queue / async | Reentrancy, Precision/Rounding, Access Control |
| Bridge / cross-chain | Bridge/Cross-chain, Access Control |
| Governance / voting | Governance, Flash Loans |
| Oracle consumer | Oracle Manipulation, Flash Loans |
| Uses external calls | Reentrancy, Delegatecall |
| Upgradeable proxy | Access Control, Delegatecall |
| Accepts native ETH | Reentrancy, Precision/Rounding |
| Callback-capable tokens | Reentrancy |
