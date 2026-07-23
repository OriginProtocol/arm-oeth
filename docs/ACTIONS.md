# Talos scheduled actions

Hardhat tasks the Talos runner (`runner.ts` → `@oplabs/talos-client`) runs on a cron
schedule, or on demand via the "Run now" button in the Talos admin UI. Each
action is defined in [`src/js/tasks/actions/<name>.ts`](../src/js/tasks/actions);
the canonical schedule — cron, enabled state, and per-row operational notes —
lives in [`migrations/seed_schedules.sql`](../migrations/seed_schedules.sql). See
[Automated Actions (Talos)](../README.md#automated-actions-talos) for how the
runner works.

> **Keep in sync** (see [`CLAUDE.md`](../CLAUDE.md)): update this file whenever a
> scheduled action is added, removed, or its behaviour changes.

Cron times are UTC. Enable state is managed in the database, not here.

The mainnet `setPrices*` actions use `--amount` as the DEX swap amount when
fetching the reference price quote. This is separate from `--buy-amount` and
`--sell-amount`, which set the buy-side liquidity-asset and sell-side base-asset
liquidity remaining on the Ethena, USDC, and WETH ARMs. If omitted, each limit is
set to the maximum `uint128` value. Liquidity amounts are integer native token
units (for example, `100000000` is 100 tokens for an asset with 6 decimals).

`--buy-price` and `--sell-price` bypass DEX-derived pricing and set an exact
pair. Both must be supplied together; `--amount` is not used in this mode.
When the Ethena or USDC action derives `--amount` from withdrawable liquidity,
it rounds the available amount up to the minimum DEX quote size of 1,000 USDe
or 1,000 USDC respectively; an explicit `--amount` override is used as supplied.

`setPricesWETH` uses the Lido pricing profile and 1Inch for `STETH,WSTETH`, and
the EtherFi pricing profile and Kyber for `EETH,WEETH`. It processes all four
bases unless `--bases` is supplied. Explicit price, liquidity, aggregator,
range, tolerance, and quote-amount flags apply to every selected base.

## Lido ARM — mainnet

| Action                    | Cron                    | Description                            |
| ------------------------- | ----------------------- | -------------------------------------- |
| `autoRequestLidoWithdraw` | `29,58 12-23,0-8 * * *` | Request Lido withdrawals from Lido ARM |
| `autoClaimLidoWithdraw`   | `32 0,12 * * *`         | Claim Lido withdrawals from Lido ARM   |
| `collectLidoFees`         | `30 12 * * *`           | Collect fees from Lido ARM             |
| `allocateLido`            | `38,08 * * * *`         | Allocate liquidity for Lido ARM        |
| `setPricesLido`           | `*/30 * * * *`          | Set prices for Lido ARM                |

## EtherFi ARM — mainnet

| Action                       | Cron            | Description                                  |
| ---------------------------- | --------------- | -------------------------------------------- |
| `autoRequestEtherFiWithdraw` | `10,40 * * * *` | Request EtherFi withdrawals from EtherFi ARM |
| `autoClaimEtherFiWithdraw`   | `40 * * * *`    | Claim EtherFi withdrawals from EtherFi ARM   |
| `collectEtherFiFees`         | `45 23 * * *`   | Collect fees from EtherFi ARM                |
| `allocateEtherFi`            | `52 * * * *`    | Allocate liquidity for EtherFi ARM           |
| `setPricesEtherFi`           | `2,32 * * * *`  | Set prices for EtherFi ARM                   |

## Ethena ARM — mainnet

| Action                      | Cron          | Description                                |
| --------------------------- | ------------- | ------------------------------------------ |
| `autoRequestEthenaWithdraw` | `12 * * * *`  | Request Ethena withdrawals from Ethena ARM |
| `autoClaimEthenaWithdraw`   | `40 * * * *`  | Claim Ethena withdrawals from Ethena ARM   |
| `collectEthenaFees`         | `45 23 * * *` | Collect fees from Ethena ARM               |
| `allocateEthena`            | `28 * * * *`  | Allocate liquidity for Ethena ARM          |
| `setPricesEthena`           | `4 * * * *`   | Set prices for Ethena ARM                  |

## USDC ARM — mainnet

| Action                    | Cron          | Description                                                          |
| ------------------------- | ------------- | -------------------------------------------------------------------- |
| `autoRequestUSDCWithdraw` | `14 * * * *`  | Request and submit Paxos redemptions of PYUSD/USDG from the USDC ARM |
| `autoClaimUSDCWithdraw`   | `44 * * * *`  | Claim USDC settled by Paxos redemptions for the USDC ARM             |
| `collectUSDCFees`         | `50 23 * * *` | Collect fees from USDC ARM                                           |
| `allocateUSDC`            | `26 * * * *`  | Allocate liquidity for USDC ARM                                      |
| `setPricesUSDC`           | `6 * * * *`   | Set prices for USDC ARM                                              |

## WETH ARM — mainnet

| Action                           | Cron                    | Description                                    |
| -------------------------------- | ----------------------- | ---------------------------------------------- |
| `autoRequestWETHLidoWithdraw`    | `29,58 12-23,0-8 * * *` | Request stETH/wstETH withdrawals from WETH ARM |
| `autoClaimWETHLidoWithdraw`      | `32 0,12 * * *`         | Claim stETH/wstETH withdrawals for WETH ARM    |
| `autoRequestWETHEtherFiWithdraw` | `10,40 * * * *`         | Request eETH/weETH withdrawals from WETH ARM   |
| `autoClaimWETHEtherFiWithdraw`   | `40 * * * *`            | Claim eETH/weETH withdrawals for WETH ARM      |
| `collectWETHFees`                | `30 12 * * *`           | Collect fees from WETH ARM                     |
| `allocateWETH`                   | `38,08 * * * *`         | Allocate liquidity for WETH ARM                |
| `setPricesWETH`                  | `*/30 * * * *`          | Set prices for all four WETH ARM base assets   |

## Origin ARM — Sonic

| Action                     | Cron            | Description                                             |
| -------------------------- | --------------- | ------------------------------------------------------- |
| `autoRequestWithdrawSonic` | `48,18 * * * *` | Request withdrawals from Origin ARM on Sonic            |
| `autoClaimWithdrawSonic`   | `10 * * * *`    | Claim withdrawals from Origin ARM on Sonic and allocate |
| `collectFeesSonic`         | `55 23 * * *`   | Collect fees from Origin ARM on Sonic                   |
| `allocateSonic`            | `1,31 * * * *`  | Allocate liquidity for Origin ARM on Sonic              |
| `setOSSiloPriceAction`     | `*/30 * * * *`  | Set prices on Sonic ARM                                 |
| `collectRewardsSonic`      | `45 23 * * *`   | Collect rewards from the Sonic harvester                |

## System

| Action        | Cron          | Description                                           |
| ------------- | ------------- | ----------------------------------------------------- |
| `healthcheck` | `*/5 * * * *` | Simple health check to verify the action system works |

## Manual-only — mainnet

Dispatched via "Run now"; the required flags are edited into the schedule's
command before each run (see notes in `seed_schedules.sql`).

| Action                           | Description                                                                          |
| -------------------------------- | ------------------------------------------------------------------------------------ |
| `pause`                          | Pause an Ethereum ARM (`--arm lido`, `etherfi`, `ethena`, `oeth`, `usdc`, or `weth`) |
| `claimRedeem`                    | Claim matured LP redeem requests on behalf of users (`--arm`, `--ids`)               |
| `setARMBufferAction`             | Set the ARM buffer (`--arm`, `--buffer`)                                             |
| `setLiquidityProviderCapsAction` | Set liquidity-provider caps (`--arm`, `--accounts`, `--cap`)                         |
| `setTotalAssetsCapAction`        | Set the total-assets cap (`--arm`, `--cap`)                                          |
