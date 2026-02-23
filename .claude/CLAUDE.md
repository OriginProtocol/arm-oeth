# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Automated Redemption Manager (ARM) by Origin Protocol. Solidity smart contracts that manage swapping and liquidity provision for LST/LRT pairs using a dual-pricing AMM model with async withdrawals.

**ARM Contracts:**
- **LidoARM** - stETH/WETH on Ethereum
- **EtherFiARM** - eETH/WETH on Ethereum
- **EthenaARM** - sUSDe/USDe on Ethereum
- **OriginARM** - OS/wS on Sonic, OETH/WETH on Ethereum

## Build & Test Commands

```bash
make install          # foundryup + soldeer + yarn
make                  # forge fmt && forge build
make test             # All tests except Fuzzer, with --fail-fast -vvv
make test-c-TestName  # Run specific test contract
make test-f-funcName  # Run specific test function
make test-unit        # Unit tests only (test/unit/**)
make test-fork        # Fork tests only (test/fork/**)
make test-smoke       # Smoke tests only (test/smoke/**)
make test-invariants  # All invariant/fuzz tests (Lido, Origin, Ethena)
make gas              # Gas report
make coverage         # LCOV coverage report
```

Linting: `forge fmt --check` (Solidity), `yarn lint` (JS), `yarn prettier:check` (JS)

## Environment Setup

Copy `.env.example` to `.env` and set `MAINNET_URL` (Ethereum RPC) and `SONIC_URL` (Sonic RPC). Fork tests require these RPC endpoints.

## Architecture

### Contract Hierarchy

`AbstractARM.sol` is the core (~1000 LOC). It implements:
- Uniswap V2 Router compatible swap interface
- ERC-4626-like LP interface (deposit/requestRedeem/claimRedeem with async 10-min claim delay)
- Dual pricing: `traderate0` (buy), `traderate1` (sell), `crossPrice` (anchor). All scaled to 1e36
- Withdrawal queue with FIFO processing
- Performance fee collection
- Lending market allocation (deposit excess liquidity, withdraw on demand)

Concrete implementations (`LidoARM.sol`, `EtherFiARM.sol`, `EthenaARM.sol`, `OriginARM.sol`) override `_externalWithdrawQueue()` and implement protocol-specific withdrawal/claim logic.

### Supporting Contracts

- **CapManager.sol** - Manages capital limits (total assets cap and per-LP caps)
- **EthenaUnstaker.sol** - Helper allowing multiple parallel sUSDe cooldowns for EthenaARM
- **ZapperARM.sol / ZapperLidoARM.sol** - Convenience wrappers for depositing native ETH
- **SonicHarvester.sol** - Collects rewards from strategies and swaps them for ARM liquidity tokens on Sonic
- **PendleOriginARMSY.sol** (`src/contracts/pendle/`) - Pendle SY adapter for ARM integration
- **Interfaces.sol** - Shared interface definitions
- **Addresses.sol** (`src/contracts/utils/`) - On-chain address registry

### Market Adapters (`src/contracts/markets/`)

`Abstract4626MarketWrapper.sol` wraps ERC-4626 lending markets (Morpho, Silo) so the ARM can deposit idle liquidity. Concrete: `MorphoMarket.sol`, `SiloMarket.sol`.

### Proxy Pattern

All ARMs are deployed behind `Proxy.sol` (EIP-1967) for upgradeability.

### Access Control

`Ownable.sol` provides base ownership with EIP-1967 storage slot for proxy admin. `OwnableOperable.sol` extends it with an operator role. Owner can set prices, manage markets, upgrade. Operator can execute operational tasks (request/claim withdrawals).

### Off-Chain Automation (`src/js/`)

- **`src/js/actions/`** - OpenZeppelin Defender Actions (auto-withdraw, auto-claim, price setting, fee collection, allocation). Bundled with rollup.
- **`src/js/tasks/`** - Hardhat tasks for admin operations.
- **`src/js/utils/`** - Shared utilities (1Inch/Kyber integration, address parsing, pricing helpers).

Actions are bundled via: `yarn rollup -c src/js/actions/rollup.config.cjs`

## Deployment

Deployment scripts are in `script/deploy/` organized by chain (`mainnet/`, `sonic/`). Numbered scripts (e.g. `011_DeployEtherFiARMScript.s.sol`) are auto-discovered and ordered by `DeployManager.s.sol`. See `script/deploy/ARCHITECTURE.md` for the full deployment framework documentation.

```bash
make deploy-mainnet       # Mainnet with verification
make deploy-sonic         # Sonic chain
make simulate             # Dry run mainnet (default)
make simulate NETWORK=sonic  # Dry run Sonic
```

## Key Conventions

- Solidity `^0.8.23`, optimizer enabled (200 runs)
- Prices are always scaled to 1e36 (`PRICE_SCALE`)
- Fee scale is 10,000 = 100% (`FEE_SCALE`)
- `token0` = swap input (bought by ARM), `token1` = swap output (sold by ARM)
- `baseAsset` = the asset being redeemed (e.g., stETH), `liquidityAsset` = the LP/quote asset (e.g., WETH)
- Test base class: `test/Base.sol` with standard accounts (alice, bob, charlie) and shared setup
- Dependencies managed by Soldeer (configured in `foundry.toml [dependencies]` section, not npm) for Solidity libs
- Prefer flat structure with early returns over deeply nested if/else blocks
