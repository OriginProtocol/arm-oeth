# Access Control Missing

External/public functions that perform privileged operations (token transfers, fund withdrawals, parameter changes) without verifying `msg.sender` authorization. The most frequent pattern in 2025 DeFi exploits — accounting for 19 incidents — because it requires no complex attack setup: the attacker simply calls an unprotected function.

**Severity**: Critical
**Checklist IDs**: F9, F16, F17, D11, D13
**Code Characteristics**: any contract with state-changing functions, proxy, token holder

## Root Cause

A function that moves value (transfers tokens, sends ETH, modifies critical parameters) lacks an access control modifier (`onlyOwner`, `onlyOperator`, role-based check). The function is either:

1. **Completely unprotected** — no modifier, no `require(msg.sender == ...)` check at all. Anyone can call it.
2. **Partially protected** — has a check that can be bypassed (e.g., accepts an arbitrary `router` address that the attacker controls, or validates a signature in a way that allows arbitrary calldata execution).
3. **Uninitialized** — uses ownership set via `initialize()` on a proxy, but the implementation was never initialized, leaving ownership claimable.

## Vulnerable Code Pattern

```solidity
// VULNERABLE — no caller restriction on fund-moving function
function swapTokensForTokens(
    address[] calldata path,
    uint256 amount,
    uint256 minOut,
    address recipient     // attacker sets to their own address
) external {
    // No: onlyOwner / onlyOperator / role check
    IERC20(path[0]).transferFrom(address(this), address(router), amount);
    router.swap(path, amount, minOut, recipient);
}
```

### Variants

**Variant A — Unvalidated callback address:**
```solidity
// VULNERABLE — accepts arbitrary router, attacker deploys fake router
function addLiquidity(address token, address router, address lpToken) external {
    IERC20(token).approve(router, type(uint256).max);
    IRouter(router).addLiquidity(token, ...);
    // Attacker's fake router calls transferFrom to drain approved tokens
}
```

**Variant B — Uninitialized proxy ownership:**
```solidity
// VULNERABLE — implementation not initialized, anyone can call initialize()
function initialize(address _owner) external {
    require(owner == address(0), "already initialized");
    owner = _owner;
}
// On the implementation contract (not proxy), owner is address(0)
// Attacker calls initialize() directly on implementation
```

**Variant C — Signature validation with side effects:**
```solidity
// VULNERABLE — "validation" function executes arbitrary calls
function isValidSigImpl(address, bytes32, bytes calldata sig, bool allowSideEffects) external {
    if (allowSideEffects) {
        (address target, bytes memory data,) = abi.decode(sig, (address, bytes, bytes));
        target.call(data);  // attacker encodes USDC.transfer(attacker, balance)
    }
}
```

## Detection Heuristic

- [ ] Does the function move tokens/ETH without `onlyOwner`, `onlyOperator`, or role-based modifier?
- [ ] Does the function accept an arbitrary external contract address and call/delegatecall it?
- [ ] Are there `transferFrom(address(this), ...)` patterns where the source is the contract itself?
- [ ] Can the function's `recipient`/`to` parameter be set to an arbitrary address by the caller?
- [ ] Is the function `external`/`public` when it should be `internal`?
- [ ] On proxies: is `initialize()` callable on the implementation contract directly?

If 2+ conditions met: **Critical**. Single unprotected fund-moving function = immediate drain.

## Fix / Mitigation

1. **Add explicit access control** on every function that moves value:
   ```solidity
   function swapTokens(...) external onlyOperator {
   ```

2. **Whitelist external addresses** — never accept arbitrary contract addresses for callbacks:
   ```solidity
   require(registeredRouters[router], "unknown router");
   ```

3. **Initialize implementations** — call `_disableInitializers()` in the constructor:
   ```solidity
   constructor() { _disableInitializers(); }
   ```

4. **Use `staticcall` for validation** — signature verification should never mutate state:
   ```solidity
   (bool success, bytes memory result) = target.staticcall(data);
   ```

## Proof (2025 Incidents)

| Protocol | Date | Loss | Variant | PoC |
|----------|------|------|---------|-----|
| Cork Protocol | 2025-01 | $12M | Unprotected function | [DeFiHackLabs](https://github.com/SunWeb3Sec/DeFiHackLabs) |
| SuperRare | 2025-01 | — | Unprotected function | [DeFiHackLabs](https://github.com/SunWeb3Sec/DeFiHackLabs) |
| 98Token | 2025-01 | ~28K USDT | A: Unprotected swap | `2025-01/98Token_exp.sol` |
| HORS | 2025-01 | 14.8 WBNB | A: Unvalidated router | `2025-01/HORS_exp.sol` |
| wKeyDAO | 2025-03 | ~767 USD | Unprotected buy function | `2025-03/wKeyDAO_exp.sol` |
| ODOS | 2025-01 | ~$50K | C: Arbitrary call in sig validation | `2025-01/ODOS_exp.sol` |

*19 total incidents in 2025 — table shows representative subset with available PoCs.*

## Related Patterns

- [arbitrary-calldata](./arbitrary-calldata.md) — overlaps when unprotected function accepts arbitrary call targets
- [signature-validation](./signature-validation.md) — ODOS incident is both access control and signature validation
- [storage-collision](./storage-collision.md) — proxy initialization gaps are an access control subpattern
