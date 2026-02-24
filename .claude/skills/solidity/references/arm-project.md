# ARM Project Reference

Project-specific patterns, conventions, and architecture for the Automated Redemption Manager (ARM) by Origin Protocol. Load this reference when writing or reviewing code in the ARM repository.

---

## Architecture Overview

### Contract Hierarchy

```
AbstractARM.sol (~1000 LOC)
├── LidoARM.sol         (stETH/WETH on Ethereum)
├── EtherFiARM.sol      (eETH/WETH on Ethereum)
├── EthenaARM.sol       (sUSDe/USDe on Ethereum)
└── OriginARM.sol       (OS/wS on Sonic, OETH/WETH on Ethereum)
```

`AbstractARM` implements the core logic. Concrete implementations override:
- `_externalWithdrawQueue()` — returns amount pending in protocol-specific withdrawal queue
- Protocol-specific withdrawal request/claim functions (e.g., Lido's `requestStETHWithdrawal`, `claimStETHWithdrawal`)

### Supporting Contracts

| Contract | Purpose |
|----------|---------|
| `CapManager.sol` | Total asset cap + per-LP deposit caps |
| `ZapperARM.sol` / `ZapperLidoARM.sol` | ETH → WETH → deposit convenience wrappers |
| `EthenaUnstaker.sol` | Parallel sUSDe cooldown management |
| `SonicHarvester.sol` | Reward collection on Sonic chain |
| `PendleOriginARMSY.sol` | Pendle SY adapter integration |

### Market Adapters

```
Abstract4626MarketWrapper.sol
├── MorphoMarket.sol    (Morpho Blue lending)
└── SiloMarket.sol      (Silo Finance lending)
```

ARM deposits idle liquidity into lending markets to earn yield. The wrapper provides a uniform interface for the ARM to allocate/withdraw from any ERC-4626 compatible market.

### Proxy Pattern

All ARMs deploy behind `Proxy.sol` (EIP-1967). The proxy admin is stored in the standard EIP-1967 admin slot. Upgrades go through the owner (governance multisig with timelock).

## Pricing System

All prices are scaled to `PRICE_SCALE = 1e36`.

### Trade Rates

- `traderate0` — price for buying token0 with token1 (ARM buys baseAsset)
- `traderate1` — price for selling token0 for token1 (ARM sells baseAsset)
- `crossPrice` — anchor price between the two rates

**Invariant:** `traderate0 <= crossPrice <= traderate1`

The spread between traderate0 and traderate1 is the ARM's profit margin.

### Price Deviation

`MAX_CROSS_PRICE_DEVIATION` limits how far crossPrice can move from 1:1 (e.g., `20e32` = 0.2%). This prevents misconfiguration from setting extreme prices.

### Token Convention

- `token0` = swap input, the asset ARM buys (e.g., stETH, eETH, sUSDe)
- `token1` = swap output, the asset ARM sells (e.g., WETH, USDe)
- `baseAsset` = the asset being redeemed through the protocol's withdrawal queue
- `liquidityAsset` = the LP/quote asset, same as token1

## Withdrawal Queue

### Data Structure

```solidity
struct WithdrawalRequest {
    address withdrawer;     // Who can claim
    bool claimed;           // Already claimed?
    uint40 claimTimestamp;  // When claimable (packed with above)
    uint128 assets;         // Amount of liquidity assets owed
    uint128 queued;         // Cumulative queued at time of request
    uint128 shares;         // Shares burned for this request
}
```

Packed into 3 storage slots. `uint40` for timestamp is safe until year 36,812.

### FIFO Processing

- `withdrawsQueued` — cumulative total of all queued withdrawal assets
- `withdrawsClaimed` — cumulative total of all claimed withdrawal assets
- `nextWithdrawalIndex` — next request ID to assign
- Claim delay: 10 minutes (`claimDelay`)

**Claim logic:** A request is claimable when:
1. `block.timestamp >= request.claimTimestamp`
2. `request.queued <= withdrawsClaimed + available liquidity`

The ARM tries to pull from lending markets first to satisfy claims before falling back to on-hand liquidity.

### Key Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `PRICE_SCALE` | `1e36` | Price precision |
| `FEE_SCALE` | `10_000` | Fee basis points (100% = 10,000) |
| `MIN_TOTAL_SUPPLY` | `1e12` | Prevent vault inflation attack |
| `DEAD_ACCOUNT` | `0x...dEaD` | Initial share recipient (dead shares) |
| `claimDelay` | `10 minutes` | Default withdrawal claim delay |

## Access Control Model

### EIP-1967 Owner

Stored in proxy storage slot `0xb53127...`. Set during proxy deployment. Can:
- Set trade rates and cross price
- Set performance fee and fee collector
- Add/remove/set active lending markets
- Upgrade implementation
- Set cap manager and operator

### Operator (OwnableOperable)

Secondary role for operational tasks. Can:
- Request withdrawals from external protocols
- Claim completed withdrawals
- Allocate liquidity to/from lending markets

### Permissionless Functions

- `deposit()` — anyone can deposit (subject to cap checks)
- `requestRedeem()` — any LP can request withdrawal
- `claimRedeem()` — anyone can claim on behalf of the withdrawer
- `swapExactTokensForTokens()` / `swapTokensForExactTokens()` — anyone can swap

## Market Adapter Pattern

### ARM Buffer and Allocation

- `armBuffer` — minimum liquidity to keep in the ARM (not allocated to markets)
- `allocateThreshold` — minimum excess over armBuffer before allocating to market

**Allocation logic:**
1. If ARM liquidity > armBuffer + allocateThreshold → deposit excess into active market
2. If ARM liquidity < needed for claim → withdraw from market to cover

### Abstract4626MarketWrapper Interface

```solidity
function deposit(uint256 assets) external returns (uint256 shares);
function withdraw(uint256 assets) external returns (uint256 withdrawn);
function totalAssets() external view returns (uint256);
```

The wrapper handles the ERC-4626 `deposit`/`redeem` translation and any protocol-specific quirks (e.g., Morpho supply queues, Silo share rounding).

## Common Gotchas

### stETH 2-Wei Rounding

stETH's `balanceOf` can be off by 1-2 wei due to share-based accounting rounding. Always use `assertApproxEqAbs(actual, expected, 2)` in tests involving stETH balances. The ARM handles this with `STETH_ERROR_ROUNDING = 2`.

### Rebasing Tokens

stETH is a rebasing token — balances change on oracle updates. The ARM's internal accounting uses WETH (non-rebasing) as the LP asset. stETH is held temporarily during the swap→withdraw→claim cycle.

### Storage Gaps

Abstract contracts must include storage gaps for upgrade safety:
```solidity
uint256[50] private __gap;
```
Reduce the gap size by 1 for each new state variable added in an upgrade.

### First Depositor Protection

`MIN_TOTAL_SUPPLY` prevents the vault inflation attack. On first deposit, dead shares are minted to `DEAD_ACCOUNT` to establish a non-zero total supply floor.

## Test Infrastructure

### Test Hierarchy

```
test/Base.sol (Base_Test_)
└── test/unit/shared/Shared.sol
    └── test/unit/shared/Modifiers.sol
        └── Concrete test files (e.g., test/unit/Deposit.t.sol)
```

### Standard Test Accounts

| Account | Role |
|---------|------|
| `alice` | Primary LP depositor |
| `bob` | Secondary LP depositor |
| `charlie` | Tertiary user |
| `deployer` | Contract deployer |
| `governor` / `owner` | Governance/admin |
| `operator` | Operational role |

### Modifier-Based Setup

Tests use composable modifiers for state setup:

```solidity
function test_ClaimRedeem_Success() external
    asGovernor                        // prank as governor
    setFee(500)                       // 5% fee
    deposit(alice, 10 ether)          // alice deposits
    requestRedeem(alice, 5 ether)     // alice requests withdrawal
    timejump(CLAIM_DELAY)             // advance past delay
{
    // Test body — only the assertion logic
    vm.prank(alice);
    arm.claimRedeem(0);
    assertEq(weth.balanceOf(alice), 5 ether);
}
```

### Fork Testing

Fork tests use real mainnet/Sonic state:
```solidity
function setUp() public override {
    vm.createSelectFork(vm.envString("MAINNET_URL"));
    // ...
}
```

Requires `MAINNET_URL` and/or `SONIC_URL` in `.env`.

### Running Tests

```bash
make test                  # All tests (except fuzzer)
make test-c-TestName       # Specific test contract
make test-f-funcName       # Specific test function
make test-unit             # Unit tests only
make test-fork             # Fork tests only
make test-invariants       # Invariant/fuzz tests
```
