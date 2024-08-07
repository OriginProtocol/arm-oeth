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

TODO

## Development

### Install

```
foundryup
forge install
forge compile
cp .env.example .env
```

In the `.env` file, set the environment variables as needed. eg `PROVIDER_URL` for the RPC endpoint.

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

## Open Zeppelin Defender

[Open Zeppelin Defender v2](https://docs.openzeppelin.com/defender/v2/) is used to manage the Operations account and automate AMM operational jobs like managing liquidity.

### Deploying Defender Autotasks

Autotasks are used to run operational jobs are specific times or intervals.

[rollup](https://rollupjs.org/) is used to bundle the Autotask source code in [/src/js/autotasks](./src/js/autotasks) into a single file that can be uploaded to Defender. The implementation was based off [Defender Autotask example using Rollup](https://github.com/OpenZeppelin/defender-autotask-examples/tree/master/rollup). The rollup config is in [/src/js/autotasks/rollup.config.cjs](./src/js/autotasks/rollup.config.cjs). The outputs are written to task-specific folders under [/src/js/autotasks/dist](./src/js/autotasks/dist/).

The [defender-autotask CLI](https://www.npmjs.com/package/@openzeppelin/defender-autotask-client) is used to upload the Action code to Defender.
For this to work, a Defender Team API key with `Manage Actions` capabilities is needed. This can be generated by a Defender team admin under the `Manage` tab on the top right of the UI and then `API Keys` on the left menu.

The following will set the Defender Team API key and bundle the Autotask code ready for upload.

```
cd ./src/js/autotasks

# Export the Defender Team API key. This is different to the Defender Relayer API key.
export API_KEY=
export API_SECRET=

npx rollup -c
```

The following will upload the different Autotask bundles to Defender.

```
# autoRequestWithdraw

# autoClaimWithdraws

```

`rollup` and `defender-autotask` can be installed globally to avoid the `npx` prefix.

## Script

### Testing script

- The deployment will happen on RPC used on the .env file, under `PROVIDER_URL`.
- If `DEPLOYER_PRIVATE_KEY` key exist, it will use it to simulate the deployment.
- Otherwise it will create an address for the test.

#### For smart contract

```
make simulate-c-ScriptContractName
# example: make simulate-c-001_OETH_ARM
```

#### For task

```
make simulate-t-taskName $(ARGS1) $(ARGS2)
# example: make simulate-task-swap FROM=0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3 TO=0x0000000000000000000000000000000000000000 AMOUNT=1234
```

### Running script

The `DEPLOYER_PRIVATE_KEY` on the `.env` is mandatory here!
It will run with the following options:

- broadcast (send transaction for real)
- slow (i.e. send tx after prior confirmed and succeeded)
- verify (verify contract on Etherscan)
- max verbosity

#### For smart contract

`ETHERSCAN_API_KEY` is mandatory here!

```
make deploy-c-ScriptContractName
```

#### For task

```
make run-t-taskName $(ARGS1) $(ARGS2)
# example: make run-task-swap FROM=0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3 TO=0x0000000000000000000000000000000000000000 AMOUNT=1234
```
