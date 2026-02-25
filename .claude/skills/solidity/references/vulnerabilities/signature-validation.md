# Signature Validation

Signature verification functions that execute arbitrary external calls as a side effect of the validation process. When the contract holds token balances or approvals, an attacker crafts a "signature" payload that encodes `token.transfer(attacker, balance)` and passes it through the validation function to drain funds. 1 incident in 2025, $50K (ODOS).

**Severity**: High
**Checklist IDs**: SIG1, SIG2, SIG3, SIG4, SIG5, C10, C11
**Code Characteristics**: signature verification, ERC-1271/ERC-6492, permit, contract holding approvals

## Root Cause

A signature validation function decodes user-supplied bytes into `(address target, bytes calldata data)` and executes `target.call(data)` as part of the verification flow. This was designed for ERC-6492 "deploy-then-verify" patterns (deploying a counterfactual wallet before checking its signature), but the target and calldata are fully attacker-controlled.

When the validation contract also holds token balances or has standing approvals from users, the attacker encodes a `transfer()` or `transferFrom()` call as the "deployment" calldata, draining funds through a function that was meant to be read-only.

## Vulnerable Code Pattern

```solidity
// VULNERABLE — signature validation executes arbitrary calls
function isValidSigImpl(
    address _signer,
    bytes32 _hash,
    bytes calldata _signature,
    bool allowSideEffects    // caller-controlled flag!
) external returns (bool) {
    // ERC-6492 detection: signature ends with magic suffix
    if (bytes32(_signature[_signature.length - 32:]) == ERC6492_DETECTION_SUFFIX) {
        // Decode attacker-controlled address + calldata from "signature"
        (address target, bytes memory callData, bytes memory innerSig) =
            abi.decode(_signature[0:_signature.length - 32], (address, bytes, bytes));

        if (allowSideEffects) {
            // VULNERABILITY: arbitrary call in contract's own context
            (bool success, ) = target.call(callData);
            // attacker encodes: USDC.transfer(attacker, USDC.balanceOf(this))
        }
    }
    // ... continues with actual signature validation
}
```

### Variants

**Variant A — ERC-6492 deploy-then-verify with side effects (ODOS, ~$50K):**
```solidity
// ODOS LimitOrderRouter on Base
// isValidSigImpl() with allowSideEffects=true
// parsed ERC-6492 suffix, executed arbitrary calldata
// Attacker encoded USDC.transfer(attacker, balance) as the "deployment"
```

**Variant B — ERC-1271 isValidSignature with external calls:**
```solidity
// Any contract implementing isValidSignature that makes external calls
// using user-supplied data during the validation process
function isValidSignature(bytes32 hash, bytes calldata sig) external view returns (bytes4) {
    // If this makes external calls based on sig content → vulnerable
}
```

**Variant C — Callback-gated side effects:**
```solidity
// Functions with boolean parameter controlling side effects
// where the flag is caller-settable from external interface
function validate(bytes calldata data, bool execute) external {
    if (execute) {
        (address target, bytes memory calldata_) = abi.decode(data, (address, bytes));
        target.call(calldata_);  // arbitrary call
    }
}
```

## Detection Heuristic

- [ ] Does any `external`/`public` function decode a `bytes` parameter into `(address, bytes)` for an external call?
- [ ] Does the contract hold token balances or have token approvals from users?
- [ ] Does any function use `address.call(data)` where both address and data derive from user input?
- [ ] Does the contract implement ERC-6492 detection (magic suffix `0x6492649264926492...`)?
- [ ] Is there a boolean/enum parameter gating side effects, callable by arbitrary addresses?
- [ ] Are there access controls on functions that perform arbitrary external calls?

If contract holds funds + exposes arbitrary call via validation: **Critical**.

## Fix / Mitigation

1. **Never execute arbitrary calls in validation functions:**
   ```solidity
   // If ERC-6492 deploy-then-verify is needed, restrict target
   require(target == KNOWN_FACTORY, "only factory");
   require(bytes4(callData) == IFactory.deploy.selector, "only deploy");
   ```

2. **Use `staticcall` for validation:**
   ```solidity
   (bool success, bytes memory result) = target.staticcall(data);
   // staticcall prevents any state modifications
   ```

3. **Separate concerns** — do not hold user funds in the validation contract:
   ```solidity
   // Validation contract: no token balances, no approvals
   // Settlement contract: holds funds, does not validate signatures
   ```

4. **Remove `allowSideEffects` from external interface:**
   ```solidity
   // Make side-effects internal-only
   function isValidSig(...) external view returns (bool) {
       return _isValidSigImpl(..., false);  // never allow side effects externally
   }
   ```

## Proof (2025 Incidents)

| Protocol | Date | Loss | Variant | PoC |
|----------|------|------|---------|-----|
| ODOS (LimitOrderRouter) | 2025-01 | ~$50K | A: ERC-6492 arbitrary call via isValidSigImpl | `2025-01/ODOS_exp.sol` |

## Related Patterns

- [access-control-missing](./access-control-missing.md) — the arbitrary call is an access control failure
- [arbitrary-calldata](./arbitrary-calldata.md) — same root pattern of user-controlled calldata execution
