# Phantom Consumption

A permissionless function reads accounting state from an external protocol, modifies internal tracking variables based on that read, then calls a user-supplied address (cast to an interface) expecting it to consume/clear the external state. An attacker deploys a contract with a no-op implementation. Because the external state is never consumed, it persists across calls, and the attacker invokes the function repeatedly — draining internal accounting to zero.

**Severity**: Critical
**Checklist IDs**: D12, D13, X9, X10, X11, F9
**Code Characteristics**: external call to user-supplied address, split read/call pattern, withdrawal queue

## Root Cause

Three interacting components:

1. **No access control** — the function is permissionless (anyone can call it).
2. **Unvalidated external call target** — the function accepts an address parameter, casts it to an interface, and calls it without verifying the address is legitimate.
3. **Split read/consume pattern** — the function reads state from contract A (external protocol) but relies on contract B (user-supplied) to consume that state. If B is attacker-controlled and does nothing, A's state persists unchanged.

The function's guard condition (e.g., `require(amount > 0)`) reads from the external protocol, not from the called contract. Since the attacker's no-op contract never triggers the external protocol to clear its state, the guard passes every time.

## Vulnerable Code Pattern

```solidity
// VULNERABLE — split read/consume with unvalidated target
uint256 public internalCounter;

function processHelper(address helper) external {
    // 1. READ from external protocol (not from `helper`)
    uint256 amount = externalProtocol.pendingAmount(helper);
    require(amount > 0, "Nothing pending");  // guard reads external state

    // 2. MODIFY internal accounting based on external read
    internalCounter -= amount;  // decrements internal tracker

    // 3. CALL user-supplied address, expecting it to consume external state
    IHelper(helper).execute();  // if helper is no-op, external state persists!
    // externalProtocol.pendingAmount(helper) STILL returns `amount`
    // Attacker calls processHelper(helper) again → drains internalCounter
}
```

### Variants

**Variant A — Registered helper bypass:**
```solidity
// LESS VULNERABLE — validates helper but doesn't verify consumption
function processHelper(address helper) external {
    require(isRegisteredHelper[helper], "Unknown helper");
    uint256 amount = externalProtocol.pendingAmount(helper);
    internalCounter -= amount;
    IHelper(helper).execute();
    // If registered helper has a bug and doesn't consume, still exploitable
}
```

**Variant B — Internal state tracking (safe):**
```solidity
// SAFE — uses internal state, not external reads
mapping(address => uint256) public helperPendingAmount;

function processHelper(address helper) external {
    uint256 amount = helperPendingAmount[helper];
    require(amount > 0, "Nothing pending");
    delete helperPendingAmount[helper];  // internal state cleared
    internalCounter -= amount;
    IHelper(helper).execute();
}
```

**Variant C — Post-call verification (safe):**
```solidity
// SAFE — verifies external state was consumed
function processHelper(address helper) external {
    uint256 amount = externalProtocol.pendingAmount(helper);
    require(amount > 0, "Nothing pending");
    internalCounter -= amount;
    IHelper(helper).execute();
    require(externalProtocol.pendingAmount(helper) == 0, "State not consumed");
}
```

## Detection Heuristic

- [ ] Function has **no access control** (no modifier restricting callers)?
- [ ] Function accepts an **address parameter** that is cast to an interface and called?
- [ ] Function **reads state from a different contract** than the one it calls (split read/call)?
- [ ] Function **modifies internal accounting** (storage writes) based on the external read?
- [ ] External state is only consumed if the called contract **performs the expected action** — but the contract is user-controlled?
- [ ] Address parameter is **not validated** against a registry/allowlist?
- [ ] Function can be called **repeatedly** with the same parameters because guard reads unconsumed external state?

If all conditions met: **Critical** — repeatable accounting drain. If most met with partial mitigation (e.g., access control exists but too broad): **High**.

## Fix / Mitigation

1. **Validate address against registry:**
   ```solidity
   require(isRegisteredHelper[helper], "Unknown helper");
   ```

2. **Track state internally** — don't re-read from external protocol:
   ```solidity
   mapping(address => uint256) internal pendingAmounts;
   // Set during request: pendingAmounts[helper] = amount;
   // Clear during claim: delete pendingAmounts[helper];
   ```

3. **Add access control:**
   ```solidity
   function processHelper(address helper) external onlyOperator { ... }
   ```

4. **Verify consumption** — check external state changed after call:
   ```solidity
   IHelper(helper).execute();
   require(externalProtocol.pendingAmount(helper) == 0, "Not consumed");
   ```

## Proof (2025 Incidents)

| Protocol | Date | Loss | Variant | PoC |
|----------|------|------|---------|-----|
| Generic Pattern | 2025 | Variable (up to 100% of tracked assets) | Split read/consume with no-op | Identified during ARM protocol audit |

## Related Patterns

- [access-control-missing](./access-control-missing.md) — permissionless function is the entry point
- [logic-flaw-state-transition](./logic-flaw-state-transition.md) — the repeated-call drain is a state transition flaw
