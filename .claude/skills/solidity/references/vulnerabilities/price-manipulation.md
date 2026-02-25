# Price Manipulation

Contract derives a token's price from real-time AMM pool reserve ratios (`balanceOf(pair)` / `getReserves()`). An attacker uses a flash loan to temporarily distort pool reserves, executes the price-dependent operation at the skewed price, then restores the pool. 14 incidents in 2025, predominantly on BSC with custom tokens.

**Severity**: High
**Checklist IDs**: D3, D4, D5, O1, O2, O5, FL5
**Code Characteristics**: AMM, swap, DEX, oracle-consumer, buy/sell functions

## Root Cause

The protocol uses **spot AMM reserves** as a price oracle. This is trivially manipulable within a single transaction:

1. The attacker flash-borrows a large quantity of one asset.
2. Swaps into the AMM pool, shifting the reserve ratio (and thus the spot price).
3. Calls the vulnerable protocol's price-dependent function at the distorted price.
4. Swaps back and repays the flash loan.

A secondary cause is **deflationary tokens that burn from pair reserves** on every transfer to the pair address. Each sell reduces the pair's token balance, inflating the apparent price. The attacker loops buy/sell cycles to progressively drain the pair.

## Vulnerable Code Pattern

```solidity
// VULNERABLE — price derived from spot pool reserves
function getPrice() public view returns (uint256) {
    uint256 reserve0 = IERC20(token0).balanceOf(pair);
    uint256 reserve1 = IERC20(token1).balanceOf(pair);
    return (reserve1 * 1e18) / reserve0;  // trivially manipulable
}

function buy(uint256 amount) external payable {
    uint256 price = getPrice();              // uses manipulated spot price
    uint256 tokens = msg.value * 1e18 / price;
    token.transfer(msg.sender, tokens);
}
```

### Variants

**Variant A — Spot-reserve price for buy/sell (wKeyDAO):**
```solidity
// buy() prices tokens from pool reserves
// Attacker flash-loans BUSD, buys wKeyDAO cheap from sale contract,
// sells on PancakeSwap. Loops 5+ times.
function buy() external payable {
    uint256 price = token.balanceOf(pair) * 1e18 / BUSD.balanceOf(pair);
    uint256 amount = msg.value / price;
    token.transfer(msg.sender, amount);
}
```

**Variant B — Deflationary burn from pair reserves (IPC, 590K USDT):**
```solidity
// VULNERABLE TOKEN — burns from pair on sells
function _transfer(address from, address to, uint256 amount) internal {
    if (to == pair) {
        uint256 burnAmt = amount * burnRate / 100;
        _burn(pair, burnAmt);  // reduces pair's token reserve → inflates price
    }
    super._transfer(from, to, amount - burnAmt);
}
// Attacker loops 16 buy/sell cycles. Each sell shrinks pair reserves.
```

**Variant C — Pre-created pool with extreme price (FourMeme, 186K USD):**
```solidity
// Launchpad migrates liquidity to DEX
function addLiquidity() external {
    // BUG: does not check if pool already exists with manipulated price
    IUniswapV3Factory(factory).createPool(token, WETH, fee);
    // Attacker front-ran and already created the pool with sqrtPriceX96
    // 368 trillion times fair value
}
```

## Detection Heuristic

- [ ] Does any function read `token.balanceOf(pair)` or `pair.getReserves()` to determine a price?
- [ ] Is the contract using a spot AMM price instead of TWAP or Chainlink oracle?
- [ ] Does the token have deflationary mechanics (burn on transfer) targeting the pair address?
- [ ] Is there a `buy()` or `sell()` function with inline price calculation?
- [ ] Does a launchpad/migration contract assume it will create the pool (vs. pool already existing)?
- [ ] Can the price-dependent function be called within a flash-loan callback?

If spot reserves used as price + no manipulation protection: **High**. If combined with deflationary burns: **Critical**.

## Fix / Mitigation

1. **Use TWAP or external oracle** — replace `balanceOf(pair)` pricing:
   ```solidity
   uint256 price = IUniswapV3Pool(pool).observe(twapWindow);
   // Or: uint256 price = chainlinkFeed.latestAnswer();
   ```

2. **Eliminate pair-targeted burns** — burn from sender, not pair:
   ```solidity
   // SAFE: burn from sender
   _burn(from, burnAmount);
   super._transfer(from, to, amount - burnAmount);
   ```

3. **Verify pool state before migration:**
   ```solidity
   address existingPool = factory.getPool(token, WETH, fee);
   require(existingPool == address(0), "pool already exists");
   ```

4. **Price sanity bounds** — reject if price deviates from reference:
   ```solidity
   require(spotPrice >= twapPrice * 95 / 100, "price too low");
   require(spotPrice <= twapPrice * 105 / 100, "price too high");
   ```

## Proof (2025 Incidents)

| Protocol | Date | Loss | Variant | PoC |
|----------|------|------|---------|-----|
| NGP Token | 2025-01 | $2M | Spot reserve price manipulation | [DeFiHackLabs](https://github.com/SunWeb3Sec/DeFiHackLabs) |
| IPC | 2025-01 | 590K USDT | B: Deflationary burn from pair | `2025-01/IPC_exp.sol` |
| FourMeme | 2025-02 | 186K USD | C: Pre-created pool with extreme price | `2025-02/FourMeme_exp.sol` |
| LAURA Token | 2025-01 | — | Spot reserve manipulation | `2025-01/LAURAToken_exp.sol` |
| MBU Token | 2025-02 | — | Spot reserve manipulation | `2025-02/MBU_exp.sol` |
| AST Token | 2025-01 | 65K USD | B: Transfer bug drains pair LP | `2025-01/Ast_exp.sol` |
| wKeyDAO | 2025-03 | ~767 USD | A: Spot-reserve price for buy() | `2025-03/wKeyDAO_exp.sol` |

*14 total incidents in 2025 — table shows representative subset.*

## Related Patterns

- [flash-loan-amplification](./flash-loan-amplification.md) — flash loans provide the capital to shift reserves
- [oracle-exploitation](./oracle-exploitation.md) — broader category; price manipulation is oracle exploitation via AMM spot
- [deflationary-token-bugs](./deflationary-token-bugs.md) — Variant B overlaps; deflationary burns enable progressive price manipulation
- [slippage-protection-missing](./slippage-protection-missing.md) — manipulated price + zero slippage = maximum extraction
