# Flash Loan Amplification

Flash loan amplification is not a standalone vulnerability but a **force multiplier** that transforms small or theoretical bugs into catastrophic exploits. The attacker borrows millions at zero cost within a single transaction, uses the capital to reach an exploitable state (inflate prices, trigger overflow, manipulate ratios), extracts value through the underlying bug, and repays. Cross-cutting across most 2025 patterns.

**Severity**: High (as amplifier)
**Checklist IDs**: FL1, FL2, FL3, FL4, FL5, O1, D2
**Code Characteristics**: any protocol accepting same-block deposits, vault, lending, oracle-consumer

## Root Cause

Flash loans break the assumption that capital deployment requires economic commitment. A protocol that is secure against an attacker with $10K may be completely broken against an attacker with $100M — and flash loans make $100M available to anyone for free.

The amplification pattern is consistent:

1. **Borrow large capital at zero cost** — from Morpho, Aave, dYdX, or Balancer.
2. **Use borrowed capital to reach exploitable state** — satisfy minimum deposits, manipulate oracle prices, inflate share ratios, trigger integer overflow at specific thresholds, generate artificial fee revenue.
3. **Extract value through the underlying vulnerability** — rounding errors become significant, share inflation becomes exploitable, oracle prices move enough to enable over-borrowing.
4. **Repay flash loan** — profit = extracted value minus flash loan fee (typically 0 or negligible).

## Vulnerable Code Pattern

```solidity
// VULNERABLE — same-block deposit + borrow allows flash loan exploitation
function deposit(uint256 amount) external {
    // No restriction on same-block withdrawal or borrow
    _mint(msg.sender, convertToShares(amount));
    asset.transferFrom(msg.sender, address(this), amount);
}

function borrow(uint256 amount) external {
    uint256 collateralValue = getCollateralValue(msg.sender);
    // Flash-loaned deposit inflates collateralValue temporarily
    require(collateralValue * LTV >= getBorrowValue(msg.sender) + amount);
    asset.transfer(msg.sender, amount);
}
```

### Amplification Mechanisms

**A — Oracle manipulation amplification:**
```solidity
// Flash-borrow → swap on DEX → move spot price
// → lending protocol uses spot price as oracle
// → attacker deposits collateral at inflated price
// → borrows maximum → repays flash loan
// Profit = borrowed amount - swap slippage cost
```

**B — Share ratio / first-depositor amplification:**
```solidity
// Flash-borrow → become first/dominant depositor
// → donate tokens to vault → inflate share-to-asset ratio
// → subsequent depositors receive fewer shares (rounding)
// → attacker redeems shares for more than deposited
```

**C — Fee/reward farming amplification (ImpermaxV3, ~$300K):**
```solidity
// Flash-borrow 10,544 WETH + 22.5M USDC
// Create concentrated Uniswap V3 position
// Execute 100+ back-and-forth swaps → generate massive fees
// reinvest() credits inflated fees to position
// Borrow against inflated position value → repay flash loan
```

**D — Integer overflow trigger (Alkimiya, ~$95.5K):**
```solidity
// Flash-borrow 10 WBTC
// Call collateralizedMint with shares = type(uint128).max + 2
// uint128(shares) truncates to 1, but collateral for full value deposited
// Transfer type(uint128).max shares away, redeem short side
// Extract full collateral → repay flash loan
```

## Detection Heuristic

- [ ] Does the protocol accept deposits and allow same-block withdrawals or borrows?
- [ ] Are collateral/health calculations based on current balances rather than time-weighted deposits?
- [ ] Can large deposits temporarily inflate share ratios, oracle prices, or collateral valuations within a single transaction?
- [ ] Does any function perform unsafe integer casting that becomes exploitable at large values?
- [ ] Are LP position fees used for collateral valuation without time-minimum requirements?
- [ ] Does the protocol use spot DEX prices rather than TWAP oracles?
- [ ] Can a withdrawal/claim be called multiple times for the same position?

If same-block deposit+borrow with no lock period: investigate which underlying vulnerabilities flash loans would amplify.

## Fix / Mitigation

1. **Same-block restrictions** — prevent deposit and borrow/withdraw in the same block:
   ```solidity
   mapping(address => uint256) public lastDepositBlock;
   function deposit(uint256 amount) external {
       lastDepositBlock[msg.sender] = block.number;
       // ...
   }
   function borrow(uint256 amount) external {
       require(block.number > lastDepositBlock[msg.sender], "same block");
       // ...
   }
   ```

2. **Safe casting** (prevents overflow trigger):
   ```solidity
   uint128 mintedShares = SafeCast.toUint128(shares);
   ```

3. **TWAP oracles** — multi-block averaging defeats single-transaction manipulation:
   ```solidity
   uint256 price = IUniswapV3Pool(pool).observe(TWAP_WINDOW);
   ```

4. **Fee accrual time bounds:**
   ```solidity
   require(block.number > position.depositBlock + MIN_ACCRUAL_BLOCKS);
   ```

5. **Minimum deposit amounts and maximum position sizes** — make exploitation uneconomical:
   ```solidity
   require(amount >= MIN_DEPOSIT, "too small");
   require(totalDeposit[msg.sender] <= MAX_POSITION, "too large");
   ```

## Proof (2025 Incidents)

| Protocol | Date | Loss | Amplified Vulnerability | PoC |
|----------|------|------|------------------------|-----|
| Unilend V2 | 2025-01 | 60 stETH | Health factor miscalculation | `2025-01/Unilend_exp.sol` |
| Alkimiya | 2025-03 | ~$95.5K | Unsafe uint128 downcast | `2025-03/Alkimiya_io_exp.sol` |
| ImpermaxV3 | 2025-04 | ~$300K | Fee accumulation manipulation | `2025-04/ImpermaxV3_exp.sol` |
| HegicOptions | 2025-02 | ~$104M | Repeated withdrawal (no flash loan needed — already critical) | `2025-02/HegicOptions_exp.sol` |

## Related Patterns

Flash loan amplification is cross-cutting. It amplifies:
- [share-price-inflation](./share-price-inflation.md) — provides capital for donation attacks
- [oracle-exploitation](./oracle-exploitation.md) — provides capital to move spot prices
- [precision-rounding](./precision-rounding.md) — provides capital to trigger overflow/rounding at scale
- [price-manipulation](./price-manipulation.md) — provides capital to shift AMM reserves
- [reward-calculation-errors](./reward-calculation-errors.md) — provides capital to inflate reward basis
- [insolvency-check-bypass](./insolvency-check-bypass.md) — provides capital for price manipulation on settlement
