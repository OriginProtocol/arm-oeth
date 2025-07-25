# Automated Redemption Manager (ARM) for Origin ETH (OETH)

Swap OETH for WETH at 1:1 ratio.

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
    */
function swapExactTokensForTokens(
    IERC20 inToken,
    IERC20 outToken,
    uint256 amountIn,
    uint256 amountOutMin,
    address to
) external;

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
    */
function swapTokensForExactTokens(
    IERC20 inToken,
    IERC20 outToken,
    uint256 amountOut,
    uint256 amountInMax,
    address to
) external;

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
```

## Deployed Contracts

### Mainnet

| Contract | Address                                    |
| -------- | ------------------------------------------ |
| Proxy    | 0x6bac785889A4127dB0e0CeFEE88E0a9F1Aaf3cC7 |
| OethARM  | 0xd8fF298eAed581f74ab845Af62C48aCF85B2f05e |

### Testnet

| Contract | Address                                    |
| -------- | ------------------------------------------ |
| Proxy    | 0xc9cC3a0A5AC839F63cCBff920FcFEd7aF3E80242 |
| OethARM  | 0x1a620B74b7d7EA9a3bD57Ca78014d78FeA7c1F1f |

### Holesky

| Contract | Address                                    |
| -------- | ------------------------------------------ |
| Proxy    | 0x8c7a302e208885ee4658E7422f9E259364cC993b |
| OethARM  | 0x699092668712E4e94B5b42Fb0aC5dA6209A67394 |

## Development

### Install

```
make install
cp .env.example .env
```

In the `.env` file, set the environment variables as needed. eg `PROVIDER_URL` for the RPC endpoint.

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

### Holesky

In the `.env` file, set `HOLESKY_DEPLOYER_PRIVATE_KEY` to an account that has funds on Holesky.
Set `ETHERSCAN_API_KEY` which can be the same key as mainnet.
Set `HOLESKY_URL` to a Holesky RPC endpoint.

```bash
make deploy-holesky
```

### Testnet

In the `.env` file, set `DEPLOYER_PRIVATE_KEY` to an account that has funds on the Tenderly Testnet.
Set `TESTNET_URL` to the Tenderly Testnet RPC endpoint.

```bash
make deploy-testnet
```

### Mainnet

In the `.env` file, set `DEPLOYER_PRIVATE_KEY`, `ETHERSCAN_API_KEY` and `PROVIDER_URL` to the mainnet values.

```bash
make deploy
```

### Sonic

In the `.env` file, set `DEPLOYER_PRIVATE_KEY` and `SONIC_URL` to the mainnet values.

```bash
make deploy-sonic
```

## Contract Verification

If the verification doesn't work with the deployment, it can be done separately with forge `verify-contract`.
For example

```
# Verify OethARM
forge verify-contract 0xd8fF298eAed581f74ab845Af62C48aCF85B2f05e OethARM  \
  --constructor-args $(cast abi-encode "constructor(address,address,address)" 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab )

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
cd ./src/js/actions

# Export the Defender Team API key. This is different to the Defender Relayer API key.
export API_KEY=
export API_SECRET=

npx rollup -c
```

The following will upload the different Action bundles to Defender.

```bash

# Set the DEBUG environment variable to oeth* for the Defender Action
npx hardhat setActionVars --id 93c010f9-05b5-460f-bd10-1205dd80a7c9
npx hardhat setActionVars --id 563d8d0c-17dc-46d3-8955-e4824864869f
npx hardhat setActionVars --id c010fb76-ea63-409d-9981-69322d27993a
npx hardhat setActionVars --id 127171fd-7b85-497e-8335-fd7907c08386
npx hardhat setActionVars --id 84b5f134-8351-4402-8f6a-fb4376034bc4
npx hardhat setActionVars --id ffcfc580-7b0a-42ed-a4f2-3f0a3add9779
npx hardhat setActionVars --id 32dbc67b-89f3-4856-8f3d-ad4dc5a09322
npx hardhat setActionVars --id 7a0cb2c9-11c2-41dd-bcd0-d7c2dbda6af6
npx hardhat setActionVars --id a9fc4c86-0506-4809-afbc-93b5e558cb68
npx hardhat setActionVars --id 12977d51-d107-45eb-ac20-45942009ab01
npx hardhat setActionVars --id 6ec46510-0b8e-48b4-a4c8-de759aad0ba4
npx hardhat setActionVars --id 6d148f26-54a6-4377-92f2-3148d572eea3

# The Defender autotask client uses generic env var names so we'll set them first from the values in the .env file
export API_KEY=
export API_SECRET=

# Mainnet
npx defender-autotask update-code 93c010f9-05b5-460f-bd10-1205dd80a7c9 ./dist/autoRequestWithdraw
npx defender-autotask update-code 563d8d0c-17dc-46d3-8955-e4824864869f ./dist/autoClaimWithdraw
npx defender-autotask update-code c010fb76-ea63-409d-9981-69322d27993a ./dist/autoRequestLidoWithdraw
npx defender-autotask update-code 127171fd-7b85-497e-8335-fd7907c08386 ./dist/autoClaimLidoWithdraw
npx defender-autotask update-code 84b5f134-8351-4402-8f6a-fb4376034bc4 ./dist/collectLidoFees
npx defender-autotask update-code ffcfc580-7b0a-42ed-a4f2-3f0a3add9779 ./dist/setPrices
npx defender-autotask update-code 32dbc67b-89f3-4856-8f3d-ad4dc5a09322 ./dist/collectFeesSonic
npx defender-autotask update-code 7a0cb2c9-11c2-41dd-bcd0-d7c2dbda6af6 ./dist/allocateSonic
npx defender-autotask update-code a9fc4c86-0506-4809-afbc-93b5e558cb68 ./dist/collectRewardsSonic
npx defender-autotask update-code 12977d51-d107-45eb-ac20-45942009ab01 ./dist/autoRequestWithdrawSonic
npx defender-autotask update-code 6ec46510-0b8e-48b4-a4c8-de759aad0ba4 ./dist/autoClaimWithdrawSonic
npx defender-autotask update-code 6d148f26-54a6-4377-92f2-3148d572eea3 ./dist/setOSSiloPriceAction
```

`rollup` and `defender-autotask` can be installed globally to avoid the `npx` prefix.

The Defender Actions need to be under 5MB in size. The [rollup-plugin-visualizer](https://www.npmjs.com/package/rollup-plugin-visualizer) can be used to visualize the size of an Action's dependencies.
A `stats.html` file is generated in the`src/js/actions` folder that can be opened in a browser to see the size of the Action's dependencies.
This will be for the last Action in the rollup config `src/js/actions/rollup.config.cjs`.
