# Automated Redemption Manager (ARM)

There are currently five ARM contracts:

1. [Lido ARM](https://docs.originprotocol.com/automated-redemption-manager-arm/steth-arm) on Ethereum with stETH as the base asset and WETH as the liquidity asset.
2. [EtherFi ARM](https://docs.originprotocol.com/automated-redemption-manager-arm/eeth-arm) on Ethereum with eETH as the base asset and WETH as the liquidity asset.
3. [Ethena ARM](https://docs.originprotocol.com/automated-redemption-manager-arm/susde-arm) on Ethereum with sUSDe as the base asset and USDe as the liquidity asset.
4. USD ARM on Ethereum with PYUSD and USDG as base assets and USDC as the liquidity asset.
5. [OS ARM](https://docs.originprotocol.com/os-arm) on Sonic with OS as the base asset and wS as the liquidity asset.

## Deployed Contracts

See the [ARM Registry](https://docs.originprotocol.com/registry/contracts/arm-registry) for the deployed contracts.

## Swap Interface

[Uniswap V2 Router](https://docs.uniswap.org/contracts/v2/reference/smart-contracts/router-02) compatible interface for swapping ERC20 tokens.

```Solidity
/**
* @notice Swaps an exact amount of input tokens for as many output tokens as possible.
* msg.sender should have already given the ARM contract an allowance of
* at least amountIn on the input token.
*
* @param inToken Input token.
* @param outToken Output token.
* @param amountIn The amount of input tokens to send.
* @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
* @param to Recipient of the output tokens.
* @return amounts The input and output token amounts.
*/
function swapExactTokensForTokens(
    IERC20 inToken,
    IERC20 outToken,
    uint256 amountIn,
    uint256 amountOutMin,
    address to
) external returns (uint256[] memory amounts);

/**
* @notice Uniswap V2 Router compatible interface. Swaps an exact amount of
* input tokens for as many output tokens as possible.
* msg.sender should have already given the ARM contract an allowance of
* at least amountIn on the input token.
*
* @param amountIn The amount of input tokens to send.
* @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
* @param path The input and output token addresses.
* @param to Recipient of the output tokens.
* @param deadline Unix timestamp after which the transaction will revert.
* @return amounts The input and output token amounts.
*/
function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
) external returns (uint256[] memory amounts);

/**
* @notice Receive an exact amount of output tokens for as few input tokens as possible.
* msg.sender should have already given the router an allowance of
* at least amountInMax on the input token.
*
* @param inToken Input token.
* @param outToken Output token.
* @param amountOut The amount of output tokens to receive.
* @param amountInMax The maximum amount of input tokens that can be required before the transaction reverts.
* @param to Recipient of the output tokens.
* @return amounts The input and output token amounts.
*/
function swapTokensForExactTokens(
    IERC20 inToken,
    IERC20 outToken,
    uint256 amountOut,
    uint256 amountInMax,
    address to
) external returns (uint256[] memory amounts);

/**
* @notice Uniswap V2 Router compatible interface. Receive an exact amount of
* output tokens for as few input tokens as possible.
* msg.sender should have already given the router an allowance of
* at least amountInMax on the input token.
*
* @param amountOut The amount of output tokens to receive.
* @param amountInMax The maximum amount of input tokens that can be required before the transaction reverts.
* @param path The input and output token addresses.
* @param to Recipient of the output tokens.
* @param deadline Unix timestamp after which the transaction will revert.
* @return amounts The input and output token amounts.
*/
function swapTokensForExactTokens(
    uint256 amountOut,
    uint256 amountInMax,
    address[] calldata path,
    address to,
    uint256 deadline
) external returns (uint256[] memory amounts);

/**
 * @notice Get the available reserves for each token in the ARM.
 * @dev Applies to the Lido, EtherFi, OETH and OS ARMs.
 * @return reserve0 The available liquidity for token0.
 * @return reserve1 The available liquidity for token1.
 */
function getReserves() external view returns (uint256 reserve0, uint256 reserve1);

/**
 * @notice Get available liquidity and base asset reserves for a supported base asset.
 * @dev Applies to the Ethena and USD ARMs.
 * For the Ethena ARM, reserveBaseAsset is sUSDe and liquidityAssets are USDe.
 * For the USD ARM, reserveBaseAsset is PYUSD or USDG and liquidityAssets are USDC.
 * Liquidity assets are net of outstanding LP withdrawal claims.
 * @param reserveBaseAsset Supported base asset whose reserve should be returned.
 * @return liquidityAssets Available liquidity assets.
 * @return baseAssetReserve Base assets held directly by the ARM.
 */
function getReserves(address reserveBaseAsset)
    external
    view
    returns (uint256 liquidityAssets, uint256 baseAssetReserve);
```

## Liquidity Provider Interface

The ARM contract provides a [Tokenized Vault Standard (ERC-4626)](https://eips.ethereum.org/EIPS/eip-4626) like interface for adding/removing liquidity to/from the ARM.
The main difference with ERC-4626 is the ARM's asynchronous withdrawal process which requests a redeem and then claims the redeem after a ten minute waiting period.
In addition, the ARM only supports `deposit` and `redeem` functions, not `mint` and `withdraw`.

```Solidity
/// @notice Preview the amount of shares that would be minted for a given amount of assets
/// @param assets The amount of liquidity assets to deposit
/// @return shares The amount of shares that would be minted
function previewDeposit(uint256 assets) external view returns (uint256 shares);

/// @notice deposit liquidity assets in exchange for liquidity provider (LP) shares.
/// The caller needs to have approved the contract to transfer the assets.
/// @param assets The amount of liquidity assets to deposit
/// @return shares The amount of shares that were minted
function deposit(uint256 assets) external returns (uint256 shares);

/// @notice deposit liquidity assets in exchange for liquidity provider (LP) shares.
/// Funds will be transferred from msg.sender.
/// @param assets The amount of liquidity assets to deposit
/// @param receiver The address that will receive shares.
/// @return shares The amount of shares that were minted
function deposit(uint256 assets, address receiver) external returns (uint256 shares);

/// @notice Preview the amount of assets that would be received for burning a given amount of shares
/// @param shares The amount of shares to burn
/// @return assets The amount of liquidity assets that would be received
function previewRedeem(uint256 shares) external view returns (uint256 assets);

/// @notice Request to redeem liquidity provider shares for liquidity assets
/// @param shares The amount of shares the redeemer wants to burn for liquidity assets
/// @return requestId The index of the withdrawal request
/// @return assets The amount of liquidity assets that will be claimable by the redeemer
function requestRedeem(uint256 shares) external returns (uint256 requestId, uint256 assets);

/// @notice Claim liquidity assets from a previous withdrawal request after the claim delay has passed.
/// This will withdraw from the active lending market if there are not enough liquidity assets in the ARM.
/// @param requestId The index of the withdrawal request
/// @return assets The amount of liquidity assets that were transferred to the redeemer
function claimRedeem(uint256 requestId) external returns (uint256 assets);

/// @notice Calculates the amount of shares for a given amount of liquidity assets
/// @dev Total assets can't be zero. The lowest it can be is MIN_TOTAL_SUPPLY
/// @param assets The amount of liquidity assets to convert to shares
/// @return shares The amount of shares that would be minted for the given assets
function convertToShares(uint256 assets) public view returns (uint256 shares);

/// @notice Calculates the amount of liquidity assets for a given amount of shares
/// @dev Total supply can't be zero. The lowest it can be is MIN_TOTAL_SUPPLY
/// @param shares The amount of shares to convert to assets
/// @return assets The amount of liquidity assets that would be received for the given shares
function convertToAssets(uint256 shares) public view returns (uint256 assets);

/// @notice The total amount of assets in the ARM, active lending market and external withdrawal queue,
/// less the liquidity assets reserved for the ARM's withdrawal queue and accrued fees.
/// @return The total amount of assets in the ARM
function totalAssets() public view virtual returns (uint256);

/// @notice The liquidity asset used for deposits and redeems. eg WETH or wS
/// Used for compatibility with ERC-4626
/// @return The address of the liquidity asset
function asset() external view virtual returns (address);
```

## Lending Platforms

The ARM token can be used as collateral on lending platforms to borrow other assets. The ARM token can not be borrowed on lending platforms as the ARM's price, or assets per share, can be increased by donating assets to the ARM. eg donating WETH or stETH to the Lido ARM will increase the ARM's token price. Increasing the price of a borrowed asset increases the borrower's loan to value (LTV) ratio which can lead to a liquidation.

## Development

### Install

```
make install
cp .env.example .env
```

In the `.env` file, set the environment variables as needed. eg `MAINNET_URL` for the RPC endpoint.

### Format and Compile

```
make
```

### Running tests

Fork and Unit tests run with the same command, as the fork is initiated on the test file itself if needed.

By default:

- verbosity is set to 3, i.e. are displayed logs, assertion errors (expected vs actual), and stack traces for failing tests.
- a summary of the test is displayed at the end.

To run all tests:

```
make test
```

To run only a test contract:

```
make test-c-TestContractName
```

To run only a specific test

```
make test-f-TestFunctionName
```

Report gas usage for tests:

```
make gas
```

## Deployment

### Store your deployer private key

We use ERC-2335 to encode private key. To be sure to never reveal it, we use the cast wallet PK management.

```bash
cast wallet import deployerKey --interactive
```

### Testnet

In the `.env` file, set `DEPLOYER_ADDRESS` (should match the privateKey you registered wit `cast wallet import deployerKey`) to an account that has funds on the Tenderly Testnet.
Set `TESTNET_URL` to the Tenderly Testnet RPC endpoint.

```bash
make deploy-testnet
```

### Mainnet

In the `.env` file, set `DEPLOYER_ADDRESS` (should match the privateKey you registered wit `cast wallet import deployerKey`), `ETHERSCAN_API_KEY` and `MAINNET_URL` to the mainnet values.

```bash
make deploy-mainnet
```

### Sonic

In the `.env` file, set `DEPLOYER_ADDRESS` (should match the privateKey you registered wit `cast wallet import deployerKey`) and `SONIC_URL` to the mainnet values.

```bash
make deploy-sonic
```

## Contract Verification

If the verification doesn't work with the deployment, it can be done separately with forge `verify-contract`.
For example

```
# Verify LidoARM
forge verify-contract 0xeC6FdCc3904F8dD6a9cbbBCC41B741df5963B42E LidoARM  \
    --constructor-args $(cast abi-encode "constructor(address,address,address,uint256,uint256,int256)" 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1 600 0 0 )


# Verify Proxy
forge verify-contract 0x6bac785889A4127dB0e0CeFEE88E0a9F1Aaf3cC7 Proxy

# Verify Proxy on Sonic
forge verify-contract --chain 146 --etherscan-api-key $SONICSCAN_API_KEY 0x2F872623d1E1Af5835b08b0E49aAd2d81d649D30 Proxy
```

### Tenderly Upload

To upload a deployed contract to Tenderly, set `TENDERLY_ACCESS_TOKEN` in your
environment.

```bash
# Sync all deployment aliases from the current chain's deployment file
yarn hardhat tenderlySync --network mainnet
yarn hardhat tenderlySync --network sonic

# Upload a deployment alias from the current chain's deployment file
yarn hardhat tenderlyUpload --network sonic --name ORIGIN_ARM
```

## Automated Actions (Talos)

The `src/js/tasks/actions/*.ts` files are hardhat tasks that handle operational jobs (allocations, fee collection, withdrawal requests, etc.). In production they're driven by a container that imports [`@talos/client`](https://github.com/oplabs/talos):

- **`runner.ts`** at repo root calls `runContainer({ product: "arm-oeth", workdir: "/app" })`. The library reads enabled schedules from the shared Talos Postgres, fires them via croner, and spawns each schedule's command as `pnpm hardhat <name> --network <chain>`.
- **`migrations/seed_schedules.sql`** is a one-time seed of the `schedules` table mirroring the old `cron/cron-jobs.ts`.
- **`src/js/tasks/lib/action.ts`** wraps the hardhat signer with `wrapSignerWithNonceQueueV6` from the library when `DATABASE_URL` is set. That routes `signer.sendTransaction` through Postgres row-locked nonce coordination.

Every scheduled action — its cadence and one-line purpose — is catalogued in [`docs/ACTIONS.md`](docs/ACTIONS.md).

### Running actions locally

Every action remains directly executable as a hardhat task on your dev machine:

```bash
pnpm hardhat allocateLido --network mainnet
pnpm hardhat healthcheck
```

**No Postgres required.** The library's nonce queue is gated by `process.env.DATABASE_URL`: if unset, the action uses a raw ethers signer with the provider's default nonce handling — exactly the behavior you had before Automaton existed. The gate is a single check at the top of the handler; no DB connection is opened.

If you opt in by setting `DATABASE_URL` (e.g., via `docker compose up`), the nonce queue engages and will try to connect to whatever that URL points at. `unset DATABASE_URL` to go back to the unwrapped path.

Signer selection (`DEPLOYER_PRIVATE_KEY` → KMS via `KMS_RELAYER_ID` → `IMPERSONATE` → hardhat first signer) lives in `src/js/utils/signers.ts`.
