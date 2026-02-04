# Automated Redemption Manager (ARM)

There are currently three ARM contracts:

1. [Lido ARM](https://docs.originprotocol.com/arm/steth-arm) on Ethereum with stETH as the base asset and WETH as the liquidity asset.
2. [OS ARM](https://docs.originprotocol.com/os-arm) on Sonic with OS as the base asset and wS as the liquidity asset.
3. OETH ARM on Ethereum with OETH as the base asset and WETH as the liquidity asset.

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
 * @notice Get the available liquidity for a each token in the ARM.
 * @return reserve0 The available liquidity for token0
 * @return reserve1 The available liquidity for token1
 */
function getReserves() external view returns (uint256 reserve0, uint256 reserve1);
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
make deploy
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

## Open Zeppelin Defender

[Open Zeppelin Defender v2](https://docs.openzeppelin.com/defender/v2/) is used to manage the Operations account and automate AMM operational jobs like managing liquidity.

### Deploying Defender Actions

Defender Actions are used to run operational jobs are specific times or intervals.

[rollup](https://rollupjs.org/) is used to bundle the Actions source code in [/src/js/actions](./src/js/actions) into a single file that can be uploaded to Defender. The implementation was based off [Defender Action example using Rollup](https://github.com/OpenZeppelin/defender-autotask-examples/tree/master/rollup). The rollup config is in [/src/js/actions/rollup.config.cjs](./src/js/actions/rollup.config.cjs). The outputs are written to task-specific folders under [/src/js/actions/dist](./src/js/actions/dist/).

The [defender-autotask CLI](https://www.npmjs.com/package/@openzeppelin/defender-autotask-client) is used to upload the Action code to Defender.
For this to work, a Defender Team API key with `Manage Actions` capabilities is needed. This can be generated by a Defender team admin under the `Manage` tab on the top right of the UI and then `API Keys` on the left menu.

The following will set the Defender Team API key and bundle the Actions code ready for upload.

```bash
# Set the DEFENDER_TEAM_KEY and DEFENDER_TEAM_SECRET env vars in the .env file

yarn rollup -c src/js/actions/rollup.config.cjs
```

The following will upload the different Action bundles to Defender.

```bash

# Set the DEBUG environment variable to oeth* for the Defender Action
yarn hardhat setActionVars --id 93c010f9-05b5-460f-bd10-1205dd80a7c9
yarn hardhat setActionVars --id 563d8d0c-17dc-46d3-8955-e4824864869f
yarn hardhat setActionVars --id c010fb76-ea63-409d-9981-69322d27993a
yarn hardhat setActionVars --id 127171fd-7b85-497e-8335-fd7907c08386
yarn hardhat setActionVars --id 84b5f134-8351-4402-8f6a-fb4376034bc4
yarn hardhat setActionVars --id ffcfc580-7b0a-42ed-a4f2-3f0a3add9779 --name ONEINCH_API_KEY # Don't forget to run `export ONEINCH_API_KEY=...` first!
yarn hardhat setActionVars --id 89658c5f-3857-4972-bef8-a5e914e13c56 # setPricesEtherFi
yarn hardhat setActionVars --id 32dbc67b-89f3-4856-8f3d-ad4dc5a09322
yarn hardhat setActionVars --id 7a0cb2c9-11c2-41dd-bcd0-d7c2dbda6af6
yarn hardhat setActionVars --id a9fc4c86-0506-4809-afbc-93b5e558cb68
yarn hardhat setActionVars --id 12977d51-d107-45eb-ac20-45942009ab01
yarn hardhat setActionVars --id 6ec46510-0b8e-48b4-a4c8-de759aad0ba4
yarn hardhat setActionVars --id 6d148f26-54a6-4377-92f2-3148d572eea3 --name ONEINCH_API_KEY # Don't forget to run `export ONEINCH_API_KEY=...` first!
yarn hardhat setActionVars --id acfbb7d6-5ea6-4ffc-a758-fa4b4f584dd1 # allocateLido
yarn hardhat setActionVars --id 6e26641e-4132-4824-bb80-7c891fd31455 # collectEtherFiFees
yarn hardhat setActionVars --id 002c2b0d-9522-4d5f-a340-9713ee43a1c3 # allocateEtherFi
yarn hardhat setActionVars --id 062cfee1-c34e-43ae-beb0-de62bc668bbd # autoRequestEtherFiWithdraw
yarn hardhat setActionVars --id 6c52f3a9-85d8-4c7f-8aee-90a95b13965c # autoClaimEtherFiWithdraw
yarn hardhat setActionVars --id 82ead29e-88f1-43bc-a5ed-503fadb3e491 # collectEthenaFees
yarn hardhat setActionVars --id 80565995-9bb2-42a0-bbd5-e15297b67050 # allocateEthena
yarn hardhat setActionVars --id 3a49c165-62d9-43a2-bef0-901ce1d59bef # autoRequestEthenaWithdraw
yarn hardhat setActionVars --id b362885c-a023-4fb5-8c04-1c33147465eb # autoClaimEthenaWithdraw

# Mainnet
yarn hardhat updateAction --id 93c010f9-05b5-460f-bd10-1205dd80a7c9 --file autoRequestWithdraw
yarn hardhat updateAction --id 563d8d0c-17dc-46d3-8955-e4824864869f --file autoClaimWithdraw
yarn hardhat updateAction --id c010fb76-ea63-409d-9981-69322d27993a --file autoRequestLidoWithdraw
yarn hardhat updateAction --id 127171fd-7b85-497e-8335-fd7907c08386 --file autoClaimLidoWithdraw
yarn hardhat updateAction --id 84b5f134-8351-4402-8f6a-fb4376034bc4 --file collectLidoFees
yarn hardhat updateAction --id ffcfc580-7b0a-42ed-a4f2-3f0a3add9779 --file setPrices
yarn hardhat updateAction --id 89658c5f-3857-4972-bef8-a5e914e13c56 --file setPricesEtherFi
yarn hardhat updateAction --id 32dbc67b-89f3-4856-8f3d-ad4dc5a09322 --file collectFeesSonic
yarn hardhat updateAction --id 7a0cb2c9-11c2-41dd-bcd0-d7c2dbda6af6 --file allocateSonic
yarn hardhat updateAction --id a9fc4c86-0506-4809-afbc-93b5e558cb68 --file collectRewardsSonic
yarn hardhat updateAction --id 12977d51-d107-45eb-ac20-45942009ab01 --file autoRequestWithdrawSonic
yarn hardhat updateAction --id 6ec46510-0b8e-48b4-a4c8-de759aad0ba4 --file autoClaimWithdrawSonic
yarn hardhat updateAction --id 6d148f26-54a6-4377-92f2-3148d572eea3 --file setOSSiloPriceAction
yarn hardhat updateAction --id acfbb7d6-5ea6-4ffc-a758-fa4b4f584dd1 --file allocateLido
yarn hardhat updateAction --id 6e26641e-4132-4824-bb80-7c891fd31455 --file collectEtherFiFees
yarn hardhat updateAction --id 002c2b0d-9522-4d5f-a340-9713ee43a1c3 --file allocateEtherFi
yarn hardhat updateAction --id 062cfee1-c34e-43ae-beb0-de62bc668bbd --file autoRequestEtherFiWithdraw
yarn hardhat updateAction --id 6c52f3a9-85d8-4c7f-8aee-90a95b13965c --file autoClaimEtherFiWithdraw
yarn hardhat updateAction --id 82ead29e-88f1-43bc-a5ed-503fadb3e491 --file collectEthenaFees
yarn hardhat updateAction --id 80565995-9bb2-42a0-bbd5-e15297b67050 --file allocateEthena
yarn hardhat updateAction --id 3a49c165-62d9-43a2-bef0-901ce1d59bef --file autoRequestEthenaWithdraw
yarn hardhat updateAction --id b362885c-a023-4fb5-8c04-1c33147465eb --file autoClaimEthenaWithdraw
```

`rollup` can be installed globally to avoid the `yarn` prefix.

The Defender Actions need to be under 5MB in size. The [rollup-plugin-visualizer](https://www.npmjs.com/package/rollup-plugin-visualizer) can be used to visualize the size of an Action's dependencies.
A `stats.html` file is generated in the`src/js/actions` folder that can be opened in a browser to see the size of the Action's dependencies.
This will be for the last Action in the rollup config `src/js/actions/rollup.config.cjs`.
