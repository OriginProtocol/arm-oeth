# Storage Collision

Multiple functions write to the same storage slot for different semantic purposes. In 2025, this manifests through EIP-1153 **transient storage** (`tstore`/`tload`) — a value written by `mint()` (user-controlled amount) overwrites an authorization address used by `uniswapV3SwapCallback()`, allowing an attacker to bypass callback validation. Combined with CREATE2 address precomputation, the attacker deploys a contract at the exact address stored in the slot. 1 incident in 2025, $353.8K (LeverageSIR).

**Severity**: Critical
**Checklist IDs**: C7, V6
**Code Characteristics**: transient storage, proxy/upgradeable, Uniswap V3 callbacks, assembly

## Root Cause

Two distinct subpatterns:

1. **Transient storage slot collision** (EIP-1153) — multiple functions use the same transient storage slot (`tstore(1, ...)` / `tload(1)`) for different purposes. Since transient storage persists for the entire transaction (cleared only at tx end), a write in function A pollutes the read in function B within the same transaction.

2. **Traditional storage collision in proxies** — the proxy's storage layout overlaps with the implementation's. After an upgrade, old data is reinterpreted as a different variable type, potentially corrupting access control or accounting.

In the LeverageSIR exploit, `mint()` stored a user-controlled amount in transient slot 1 via `tstore(1, amount)`. The `uniswapV3SwapCallback()` function read from the same slot via `tload(1)` to determine the authorized callback address. The attacker:
1. Called `mint()` with fake ERC-20 tokens to write a specific value into slot 1.
2. Used CREATE2 (ImmutableCreate2Factory) to deploy a contract at exactly that address.
3. Called `uniswapV3SwapCallback()` from the deployed contract, passing the `tload(1)` check.
4. Drained USDC, WBTC, and WETH from the vault.

## Vulnerable Code Pattern

```solidity
// VULNERABLE — transient storage slot shared across functions
contract Vault {
    // Function A: stores callback authorization
    function _performSwap(...) internal {
        assembly { tstore(1, expectedCallbackAddress) }
        IUniswapV3Pool(pool).swap(...);
    }

    // Function B: callback reads authorization from same slot
    function uniswapV3SwapCallback(...) external {
        address authorized;
        assembly { authorized := tload(1) }  // reads whatever was last written
        IERC20(token).transfer(authorized, amount);  // sends to "authorized"
    }

    // Function C: ALSO writes to slot 1 with user-controlled value
    function mint(...) external returns (uint256 amount) {
        // ... computation with fake tokens returns attacker-controlled amount ...
        assembly { tstore(1, amount) }  // overwrites callback authorization!
    }
}
```

### Variants

**Variant A — Transient storage slot collision (LeverageSIR, ~$353.8K):**
```solidity
// mint() uses tstore(1, amount) where amount is attacker-controlled
// via fake ERC-20 token contracts that return crafted values
// Attacker sets amount = address of CREATE2-deployed contract
// Then that contract calls uniswapV3SwapCallback(), passes tload(1) check
// Drains all USDC, WBTC, WETH from vault
```

**Variant B — Traditional proxy storage collision:**
```solidity
// Proxy:          slot 0 = admin address
// Implementation: slot 0 = totalSupply (uint256)
// If implementation writes to totalSupply, it overwrites admin
// Or: old implementation stored mapping at slot X,
//     new implementation stores a different variable at slot X
```

**Variant C — CREATE2 address grinding for authorization:**
```solidity
// Systems that use contract addresses for authorization are vulnerable
// if the address can be predicted via CREATE2
// Attacker precomputes: CREATE2(factory, salt, initCodeHash)
// Deploys contract at exact address needed to pass auth check
```

## Detection Heuristic

- [ ] Does the contract use `tstore`/`tload`? Map ALL slot indices across ALL functions.
- [ ] Can any two functions write to the same transient storage slot with different meanings?
- [ ] Is transient storage used for authorization (callback addresses, permitted callers)?
- [ ] Can the value written to a transient slot be influenced by external input (return values from user-supplied contracts)?
- [ ] Does the contract interact with CREATE2 factories? Can an attacker deploy at a predictable address?
- [ ] For proxies: does the storage layout overlap between proxy and implementation?
- [ ] Are fake/malicious ERC-20 tokens passable as parameters?

If transient storage reused across functions with user-controlled writes: **Critical**.

## Fix / Mitigation

1. **Unique transient storage slots per purpose:**
   ```solidity
   // SAFE: use keccak256-derived slots instead of small integers
   bytes32 constant AUTH_SLOT = keccak256("vault.callback.authorized");
   bytes32 constant AMOUNT_SLOT = keccak256("vault.mint.amount");
   assembly {
       tstore(AUTH_SLOT, authorizedAddress)
       tstore(AMOUNT_SLOT, amount)
   }
   ```

2. **Do not derive authorization from arithmetic values:**
   ```solidity
   // Never: tstore(1, computedAmount) then tload(1) as address
   // Keep auth data and computation data in separate domains
   ```

3. **Validate callback callers explicitly** — derive pool address, don't store it:
   ```solidity
   function uniswapV3SwapCallback(...) external {
       // SAFE: compute expected pool from factory + tokens + fee
       address expectedPool = computePoolAddress(factory, token0, token1, fee);
       require(msg.sender == expectedPool, "unauthorized");
   }
   ```

4. **Restrict token parameters** — validate against allowlist:
   ```solidity
   require(allowedTokens[token0] && allowedTokens[token1], "unknown token");
   ```

5. **Clear transient storage immediately after use:**
   ```solidity
   address authorized;
   assembly {
       authorized := tload(AUTH_SLOT)
       tstore(AUTH_SLOT, 0)  // clear immediately
   }
   ```

6. **For proxies: use EIP-1967 storage slots** with keccak256-derived locations.

## Proof (2025 Incidents)

| Protocol | Date | Loss | Variant | PoC |
|----------|------|------|---------|-----|
| LeverageSIR | 2025-03 | ~$353.8K (USDC+WBTC+WETH) | A: Transient storage slot collision + CREATE2 | `2025-03/LeverageSIR_exp.sol` |

## Related Patterns

- [precision-rounding](./precision-rounding.md) — the stored value is arithmetic (amount) reinterpreted as address
- [access-control-missing](./access-control-missing.md) — the authorization bypass is fundamentally an access control failure
