// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IWETH} from "src/contracts/Interfaces.sol";
import {IERC20} from "src/contracts/Interfaces.sol";

interface Wrapper {
    function wrap(uint256 amount) external returns (uint256);
    function unwrap(uint256 amount) external returns (uint256);
}

contract ARMRouter {
    ////////////////////////////////////////////////////
    ///                 Structs and Enums
    ////////////////////////////////////////////////////
    struct Config {
        /// @notice Function signature for the ARM contract method.
        /// @dev Should be 0x0 if address is an ARM.
        bytes4 sig;
        /// @notice Address of the ARM or Wrapper contract.
        address addr;
    }

    ////////////////////////////////////////////////////
    ///                 Constants and Immutables
    ////////////////////////////////////////////////////
    /// @notice Address of the WETH token contract.
    IWETH public immutable WETH;
    /// @notice Price scale used for traderate calculations.
    uint256 public constant PRICE_SCALE = 1e36;
    /// @notice Function signature for swapExactTokensForTokens(uint256,uint256,address[],address,uint256)
    bytes4 private constant SIG_EXACT_FOR = 0x38ed1739;
    /// @notice Function signature for swapTokensForExactTokens(uint256,uint256,address[],address,uint256)
    bytes4 private constant SIG_FOR_EXACT = 0x8803dbee;

    ////////////////////////////////////////////////////
    ///                 State Variables
    ////////////////////////////////////////////////////
    /// @notice Mapping to store ARM addresses for token pairs.
    mapping(address => mapping(address => Config)) internal configs;

    ////////////////////////////////////////////////////
    ///                 Constructor
    ////////////////////////////////////////////////////
    constructor(address _weth) {
        WETH = IWETH(_weth);
    }

    ////////////////////////////////////////////////////
    ///                 Modifiers
    ////////////////////////////////////////////////////
    /// @notice Ensures that the transaction is executed before the specified deadline.
    /// @param deadline The timestamp by which the transaction must be completed.
    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
        _;
    }

    ////////////////////////////////////////////////////
    ///                 Swap Functions
    ////////////////////////////////////////////////////
    /// @notice Swaps an exact amount of input tokens for as many output tokens as possible, along the route determined by the path.
    /// @dev This is a simplified version that handles swaps in a loop without fetching amounts beforehand.
    /// @param amountIn The exact amount of input tokens to swap.
    /// @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
    /// @param path An array of token addresses representing the swap path.
    /// @param to The address that will receive the output tokens.
    /// @param deadline The timestamp by which the transaction must be completed.
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        // Transfer the input tokens from the sender to this contract
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        // Perform the swaps along the path
        amounts = _swaps(amountIn, path, to, SIG_EXACT_FOR);

        // Ensure the output amount meets the minimum requirement
        require(amounts[amounts.length - 1] >= amountOutMin, "ARMRouter: INSUFFICIENT_OUTPUT_AMOUNT");
    }

    /// @notice Swaps an exact amount of ETH for as many output tokens as possible, along the route determined by the path.
    /// @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
    /// @param path An array of token addresses representing the swap path.
    /// @param to The address that will receive the output tokens.
    /// @param deadline The timestamp by which the transaction must be completed.
    /// @return amounts An array of token amounts for each step in the swap path.
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        // Ensure the first token in the path is WETH
        require(path[0] == address(WETH), "ARMRouter: INVALID_PATH");

        // Wrap ETH to WETH
        WETH.deposit{value: msg.value}();

        // Perform the swaps along the path
        amounts = _swaps(msg.value, path, to, SIG_EXACT_FOR);

        // Ensure the output amount meets the minimum requirement
        require(amounts[amounts.length - 1] >= amountOutMin, "ARMRouter: INSUFFICIENT_OUTPUT_AMOUNT");
    }

    /// @notice Internal function to perform swaps along the specified path.
    /// @param amountIn The amount of input tokens to swap.
    /// @param path The swap path as an array of token addresses.
    /// @param to The address that will receive the output tokens.
    /// @param sig The function signature for the swap.
    /// @return amounts An array of token amounts for each step in the swap path.
    function _swaps(uint256 amountIn, address[] memory path, address to, bytes4 sig)
        internal
        returns (uint256[] memory amounts)
    {
        // Initialize the amounts array
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        // Perform the swaps along the path
        uint256 len = path.length;
        for (uint256 i; i < len - 1; i++) {
            // Build intermediate path
            address[] memory intermediate = new address[](2);
            intermediate[0] = path[i];
            intermediate[1] = path[i + 1];

            // Get ARM or Wrapper config
            Config memory config = getConfigFor(intermediate);

            if (config.sig == bytes4(0)) {
                // It's an ARM swap
                config.sig = sig;

                // Determine receiver address
                address receiver = i < len - 2 ? address(this) : to;

                // Perform the ARM swap
                amounts[i + 1] = _armSwap(config, amounts[i], intermediate, receiver, type(uint256).max);
            } else {
                // It's a wrap/unwrap operation
                amounts[i + 1] = _wrapOrUnwrap(config, amounts[i]);

                // If this is the last swap, transfer to the recipient
                if (i == len - 2) IERC20(path[i + 1]).transfer(to, amounts[i + 1]);
            }
        }
    }

    ////////////////////////////////////////////////////
    ///                 Internal Logic
    ////////////////////////////////////////////////////
    /// @notice Internal function to perform a token swap using the specified ARM configuration.
    /// @param config The ARM configuration containing the function signature and address.
    /// @param amountIn The amount of input tokens to swap.
    /// @param path The swap path as an array of token addresses.
    /// @param to The address that will receive the output tokens.
    /// @param deadline The timestamp by which the transaction must be completed. Maybe unused in some ARMs.
    /// @return amountOut The amount of output tokens received from the swap.
    function _armSwap(Config memory config, uint256 amountIn, address[] memory path, address to, uint256 deadline)
        internal
        returns (uint256 amountOut)
    {
        // Call the ARM contract's swap function
        (bool success, bytes memory data) =
            config.addr.call(abi.encodeWithSelector(config.sig, amountIn, 0, path, to, deadline));

        // Ensure the swap was successful
        require(success, "ARMRouter: SWAP_FAILED");

        // Decode the output amounts
        uint256[] memory amounts = abi.decode(data, (uint256[]));
        amountOut = amounts[1];
    }

    function _wrapOrUnwrap(Config memory config, uint256 amountIn) internal returns (uint256 amountOut) {
        // Call the Wrapper contract's wrap/unwrap function
        (bool success, bytes memory data) = config.addr.call(abi.encodeWithSelector(config.sig, amountIn));

        // Ensure the wrap/unwrap was successful
        require(success, "ARMRouter: WRAP_UNWRAP_FAILED");

        // Decode the output amount
        amountOut = abi.decode(data, (uint256));
    }

    ////////////////////////////////////////////////////
    ///                 View Functions
    ////////////////////////////////////////////////////
    /// @notice Given a pair of tokens, returns the address of the associated ARM.
    /// @param tokenPair An array containing the addresses of the two tokens.
    /// @return arm The address of the associated ARM.
    function getConfigFor(address[] memory tokenPair) public view returns (Config memory arm) {
        // Fetch the ARM configuration for the token pair
        arm = configs[tokenPair[0]][tokenPair[1]];

        // Ensure the ARM configuration exists
        require(arm.addr != address(0), "ARMRouter: ARM_NOT_FOUND");
    }

    ////////////////////////////////////////////////////
    ///                 Owner Functions
    ////////////////////////////////////////////////////
    function registerConfig(address tokenA, address tokenB, bytes4 sig, address armAddress) external {
        // Max approval for router to interact with ARMs
        IERC20(tokenA).approve(armAddress, type(uint256).max);
        IERC20(tokenB).approve(armAddress, type(uint256).max);

        // Store the ARM configuration
        configs[tokenA][tokenB] = Config({sig: sig, addr: armAddress});
    }
}
