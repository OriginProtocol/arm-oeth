# Arbitrary Calldata / External Call Injection

Contracts that accept user-supplied calldata and pass it to external calls without validating the target address or function selector. The attacker crafts calldata encoding `transferFrom(victim, attacker, amount)` and executes it through the vulnerable contract, draining users who have granted token approvals. 4 incidents in 2025, up to $4.5M (1inch Fusion).

**Severity**: Critical
**Checklist IDs**: D11, D13, F5, X5
**Code Characteristics**: DEX aggregator, settlement contract, router, any contract holding user approvals

## Root Cause

The contract exposes a function that:
1. Accepts an `address target` and `bytes calldata data` from the caller.
2. Executes `target.call(data)` or `target.call{value: v}(data)` without restricting which addresses can be called or which function selectors are allowed.
3. The contract (or a router it delegates through) holds standing token approvals from users.

The attacker sets `target = USDC` and `data = transferFrom(victim, attacker, amount)`, executing the transfer through the vulnerable contract's approval context.

A secondary cause is **assembly-level calldata corruption** — Yul code performs unchecked arithmetic on calldata offsets, causing integer overflow that overwrites critical parameters with attacker-controlled data.

## Vulnerable Code Pattern

```solidity
// VULNERABLE — executor receives arbitrary calldata
function swap(SwapParams calldata params) external {
    // params.executor and params.executeParams are attacker-controlled
    (bool success,) = params.executor.call(params.executeParams);
    //                 ^^^^^^^^^^^^^^^^    ^^^^^^^^^^^^^^^^^^^^^^
    //                 attacker: USDC addr  attacker: transferFrom(victim, attacker, bal)
    require(success);
}
```

### Variants

**Variant A — Direct arbitrary external call (Kame, Bebop):**
```solidity
// Settlement executes arbitrary interaction array
function settle(Order calldata order, JamInteraction[] calldata interactions) external {
    for (uint i = 0; i < interactions.length; i++) {
        (bool success,) = interactions[i].to.call{value: interactions[i].value}(
            interactions[i].data  // attacker: transferFrom(victim, attacker, amount)
        );
    }
}
```

**Variant B — Assembly overflow corrupts calldata (1inch Fusion, $4.5M):**
```solidity
// In Yul: unchecked add overflows, corrupting memory layout
// add(interactionLength, suffixLength) overflows to 0
// Suffix data lands in the middle of calldata,
// overwriting the interaction parameter with attacker-controlled bytes
// Result: attacker redirects funds to their address
```

**Variant C — Approval-draining via resolver pattern:**
```solidity
// DEX aggregator has standing approvals from users for "gasless" swaps
// Resolver submits a batch that includes a transferFrom call
// disguised as a legitimate settlement interaction
function fillOrder(bytes calldata interaction) external {
    (address target, bytes memory data) = abi.decode(interaction, (address, bytes));
    target.call(data);  // no whitelist, no selector check
}
```

## Detection Heuristic

- [ ] Does the contract accept a target address and calldata from user input and execute via `.call()`?
- [ ] Does the contract hold token approvals from users (or route through a router that does)?
- [ ] Are there Yul/assembly blocks performing arithmetic on calldata offsets without overflow checks?
- [ ] Is the external call target validated against a whitelist?
- [ ] Is there a function selector restriction (block `transferFrom`, `approve`, `transfer`)?
- [ ] Can `msg.sender` bypass interaction validation?

If contract holds approvals + accepts arbitrary call targets: **Critical**.

## Fix / Mitigation

1. **Whitelist call targets:**
   ```solidity
   require(allowedTargets[target], "unauthorized target");
   ```

2. **Validate function selectors** — block dangerous selectors:
   ```solidity
   bytes4 selector = bytes4(data[:4]);
   require(selector != IERC20.transferFrom.selector, "blocked selector");
   require(selector != IERC20.approve.selector, "blocked selector");
   ```

3. **Use checked arithmetic in assembly:**
   ```yul
   // SAFE: explicit overflow check
   let total := add(interactionLength, suffixLength)
   if lt(total, interactionLength) { revert(0, 0) }  // overflow check
   ```

4. **Eliminate standing approvals** — use Permit2 or per-transaction approvals:
   ```solidity
   // Instead of: user approves router for max amount
   // Use: user signs Permit2 for exact amount per swap
   ```

5. **Require signed interactions** — all call targets and data must be signed by the order maker.

## Proof (2025 Incidents)

| Protocol | Date | Loss | Variant | PoC |
|----------|------|------|---------|-----|
| 1inch Fusion | 2025-03 | ~$4.5M | B: Yul overflow corrupts calldata, redirects USDC | `2025-03/OneInchFusionV1SettlementHack.sol_exp.sol` |
| Bebop (JamSettlement) | 2025 | ~$21K | A: Arbitrary JamInteraction[] executes transferFrom | [DeFiHackLabs](https://github.com/SunWeb3Sec/DeFiHackLabs) |
| Kame (AggregationRouter) | 2025 | ~$18K | A: User-supplied executor + executeParams | [DeFiHackLabs](https://github.com/SunWeb3Sec/DeFiHackLabs) |

## Related Patterns

- [access-control-missing](./access-control-missing.md) — unprotected arbitrary call is an access control failure
- [signature-validation](./signature-validation.md) — ODOS exploited similar pattern via signature validation with side effects
