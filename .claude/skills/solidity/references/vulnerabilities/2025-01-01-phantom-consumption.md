---
date: 2025-01-01
protocol: Generic Pattern (Phantom Consumption)
chain: Any
amount_lost: Variable (up to 100% of tracked assets)
category: Access Control / Accounting / Interface Impersonation
severity: Critical
recovered: N/A
---

# Phantom Consumption Attack Pattern

## Summary

A permissionless function reads accounting state from an external protocol,
modifies internal tracking variables based on that read, then calls a
user-supplied address (cast to an interface) expecting it to consume/clear
the external state. An attacker deploys a contract with a no-op implementation
of the expected interface. Because the external state is never consumed, it
persists across calls, and the attacker can invoke the function repeatedly in
a single transaction — draining the internal accounting variable to zero.

## Root Cause

The vulnerability has three interacting components:

1. **No access control**: The function is permissionless (anyone can call it)
2. **Unvalidated external call target**: The function accepts an address
   parameter, casts it to an interface, and calls it — but doesn't verify
   the address is a legitimate/registered contract
3. **Split read/consume pattern**: The function reads state from contract A
   (the external protocol) but relies on contract B (the user-supplied address)
   to consume that state. If B is attacker-controlled and does nothing, A's
   state persists unchanged

The key insight: the function's guard condition (e.g., `require(amount > 0)`)
reads from the external protocol, not from the called contract. Since the
attacker's no-op contract never triggers the external protocol to clear its
state, the guard condition passes every time.

## Vulnerable Code Pattern

```solidity
// VULNERABLE PATTERN
// State tracked internally
uint256 public internalCounter;

function processHelper(address helper) external {
    // 1. READ from external protocol (not from `helper`)
    uint256 amount = externalProtocol.pendingAmount(helper);
    require(amount > 0, "Nothing pending");  // Guard reads external state

    // 2. MODIFY internal accounting based on external read
    internalCounter -= amount;  // Decrements internal tracker

    // 3. CALL user-supplied address, expecting it to consume external state
    IHelper(helper).execute();  // If helper is no-op, external state persists!
    // externalProtocol.pendingAmount(helper) STILL returns `amount`
    // Attacker calls processHelper(helper) again → drains internalCounter
}
```

Compare with the safe version where the function uses a registered helper:

```solidity
// SAFE PATTERN — validates helper is registered
mapping(address => bool) public isRegisteredHelper;

function processHelper(address helper) external {
    require(isRegisteredHelper[helper], "Unknown helper");
    // ... rest of function
}
```

Or even safer — track state internally:

```solidity
// SAFEST PATTERN — uses internal state, not external reads
mapping(address => uint256) public helperPendingAmount;

function processHelper(address helper) external {
    uint256 amount = helperPendingAmount[helper];
    require(amount > 0, "Nothing pending");
    delete helperPendingAmount[helper];  // Internal state cleared
    internalCounter -= amount;
    IHelper(helper).execute();
}
```

## Detection Heuristic

Look for ALL of these conditions in a single function:

- [ ] Function has **no access control** (no modifier restricting callers)
- [ ] Function accepts an **address parameter** that is cast to an interface and called
- [ ] Function **reads state from a different contract** than the one it calls (split read/call)
- [ ] Function **modifies internal accounting** (storage writes) based on the external read
- [ ] The external state is only consumed if the called contract **actually performs the expected action** — but the called contract is user-controlled
- [ ] The address parameter is **not validated** against a registry/allowlist
- [ ] The function can be called **multiple times** with the same parameters because the guard condition reads unconsumed external state

If all conditions are met: **Critical** — repeatable accounting drain.
If most conditions are met but with partial mitigation (e.g., access control exists but is too broad): **High**.

## Fix / Mitigation

Three levels of defense (use at least one, ideally two):

1. **Validate the address against a registry**: Maintain a mapping or array of
   legitimate helper addresses. Reject unknown addresses.
   ```solidity
   require(isRegisteredHelper[helper], "Unknown helper");
   ```

2. **Track state internally instead of reading externally**: Store the expected
   amount when the request is made, and use that stored value for the
   decrement — don't re-read from the external protocol.
   ```solidity
   mapping(address => uint256) internal pendingAmounts;
   // Set during request: pendingAmounts[helper] = amount;
   // Clear during claim: amount = pendingAmounts[helper]; delete pendingAmounts[helper];
   ```

3. **Add access control**: Restrict the function to operator/owner roles.
   Even if the address isn't validated, only trusted callers can invoke it.

4. **Verify external state was actually consumed**: After the call to the
   user-supplied address, verify the external state changed:
   ```solidity
   IHelper(helper).execute();
   require(externalProtocol.pendingAmount(helper) == 0, "State not consumed");
   ```

## References

- Pattern identified during ARM protocol audit (2025)
- Related to: unvalidated callback targets, accounting manipulation, phantom function calls
