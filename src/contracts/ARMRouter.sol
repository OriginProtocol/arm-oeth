// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IWETH} from "src/contracts/Interfaces.sol";
import {IERC20} from "src/contracts/Interfaces.sol";
import {AbstractARM} from "src/contracts/AbstractARM.sol";

interface Wrapper {
    function wrap(uint256 amount) external returns (uint256);
    function unwrap(uint256 amount) external returns (uint256);
}

contract ARMRouter {
    ////////////////////////////////////////////////////
    ///                 Structs and Enums
    ////////////////////////////////////////////////////
    enum SwapType {
        ARM,
        WRAPPER
    }

    struct Config {
        /// @notice Type of swap (ARM or Wrap).
        SwapType swapType;
        /// @notice Address of the ARM or Wrapper contract.
        address addr;
        /// @notice Function signature for wrap/unwrap.
        bytes4 wrapSig;
        /// @notice Function signature for price query on wrapper.
        bytes4 priceSig;
    }

    ////////////////////////////////////////////////////
    ///                 Constants and Immutables
    ////////////////////////////////////////////////////
    /// @notice Address of the WETH token contract.
    IWETH public immutable WETH;
    /// @notice Price scale used for traderate calculations.
    uint256 public constant PRICE_SCALE = 1e36;

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
        amounts = _swapExactTokenFor(amountIn, path, to);

        // Ensure the output amount meets the minimum requirement
        require(amounts[amounts.length - 1] >= amountOutMin, "ARMRouter: INSUFFICIENT_OUTPUT_AMOUNT");
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        // Calculate the required input amounts for the desired output
        amounts = _getAmountsIn(amountOut, path);

        // Ensure the required input does not exceed the maximum allowed
        require(amounts[0] <= amountInMax, "ARMRouter: EXCESSIVE_INPUT_AMOUNT");

        // Transfer the input tokens from the sender to this contract
        IERC20(path[0]).transferFrom(msg.sender, address(this), amounts[0]);

        // Perform the swaps along the path
        _swapsForExactTokens(amounts, path, to);
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
        amounts = _swapExactTokenFor(msg.value, path, to);

        // Ensure the output amount meets the minimum requirement
        require(amounts[amounts.length - 1] >= amountOutMin, "ARMRouter: INSUFFICIENT_OUTPUT_AMOUNT");
    }

    ////////////////////////////////////////////////////
    ///                 Internal Logic
    ////////////////////////////////////////////////////
    /// @notice Internal function to perform swaps along the specified path.
    /// @param amountIn The amount of input tokens to swap.
    /// @param path The swap path as an array of token addresses.
    /// @param to The address that will receive the output tokens.
    /// @return amounts An array of token amounts for each step in the swap path.
    function _swapExactTokenFor(uint256 amountIn, address[] memory path, address to)
        internal
        returns (uint256[] memory amounts)
    {
        // Initialize the amounts array
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        // Perform the swaps along the path
        uint256 len = path.length;
        for (uint256 i; i < len - 1; i++) {
            // Get ARM or Wrapper config
            Config memory config = getConfigFor(path[i], path[i + 1]);

            if (config.swapType == SwapType.ARM) {
                // Determine receiver address
                address receiver = i < len - 2 ? address(this) : to;

                // Build intermediate path
                address[] memory intermediate = new address[](2);
                intermediate[0] = path[i];
                intermediate[1] = path[i + 1];

                uint256[] memory obtained = AbstractARM(config.addr)
                    .swapExactTokensForTokens(amounts[i], 0, intermediate, receiver, type(uint256).max);

                // Perform the ARM swap
                amounts[i + 1] = obtained[1];
            } else {
                // Call the Wrapper contract's wrap/unwrap function
                (bool success, bytes memory data) = config.addr.call(abi.encodeWithSelector(config.wrapSig, amounts[i]));

                // Ensure the wrap/unwrap was successful
                require(success, "ARMRouter: WRAP_UNWRAP_FAILED");

                // It's a wrap/unwrap operation
                amounts[i + 1] = abi.decode(data, (uint256));

                // If this is the last swap, transfer to the recipient
                if (i == len - 2) IERC20(path[i + 1]).transfer(to, amounts[i + 1]);
            }
        }
    }

    /// @notice Internal function to perform swaps for exact output amounts along the specified path.
    /// @param amounts The array of token amounts for each step in the swap path.
    /// @param path The swap path as an array of token addresses.
    /// @param to The address that will receive the output tokens.
    function _swapsForExactTokens(uint256[] memory amounts, address[] memory path, address to) internal {
        for (uint256 i = 0; i < path.length - 1; i++) {
            address tokenA = path[i];
            address tokenB = path[i + 1];

            // Get ARM or Wrapper config
            Config memory config = getConfigFor(tokenA, tokenB);

            if (config.swapType == SwapType.ARM) {
                // Determine receiver address
                address receiver = i < path.length - 2 ? address(this) : to;

                // Perform the ARM swap
                AbstractARM(config.addr)
                    .swapTokensForExactTokens(IERC20(tokenA), IERC20(tokenB), amounts[i + 1], amounts[i], receiver);
            } else {
                // Call the Wrapper contract's wrap/unwrap function
                (bool success,) = config.addr.call(abi.encodeWithSelector(config.wrapSig, amounts[i]));

                // Ensure the wrap/unwrap was successful
                require(success, "ARMRouter: WRAP_UNWRAP_FAILED");

                // If this is the last swap, transfer to the recipient
                if (i == path.length - 2) IERC20(tokenB).transfer(to, amounts[i + 1]);
            }
        }
    }

    /// @notice Calculates the required input amounts for a desired output amount along the specified path.
    /// @param amountOut The desired output amount of the final token in the path.
    /// @param path The swap path as an array of token addresses.
    /// @return amounts An array of token amounts for each step in the swap path.
    function _getAmountsIn(uint256 amountOut, address[] memory path) internal returns (uint256[] memory amounts) {
        // Ensure the path has at least two tokens
        require(path.length >= 2, "ARMRouter: INVALID_PATH");

        // Initialize the amounts array
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;

        // Calculate required input amounts in reverse order
        for (uint256 i = path.length - 1; i > 0; i--) {
            amounts[i - 1] = _getAmountIn(amounts[i], path[i - 1], path[i]);
        }
    }

    /// @notice Calculates the required input amount for a desired output amount between two tokens.
    /// @param amountOut The desired output amount.
    /// @param tokenA The address of the input token.
    /// @param tokenB The address of the output token.
    /// @return amountIn The required input amount.
    function _getAmountIn(uint256 amountOut, address tokenA, address tokenB) internal returns (uint256 amountIn) {
        // Get ARM or Wrapper config
        Config memory config = getConfigFor(tokenA, tokenB);

        if (config.swapType == SwapType.ARM) {
            // Fetch token0 from ARM
            IERC20 token0 = AbstractARM(config.addr).token0();

            // Get traderate based on token position
            uint256 traderate = tokenA == address(token0)
                ? AbstractARM(config.addr).traderate0()
                : AbstractARM(config.addr).traderate1();

            // Calculate required input amount
            amountIn = ((amountOut * PRICE_SCALE) / traderate) + 3;
        } else {
            // Call the Wrapper contract's price query function
            (bool success, bytes memory data) = config.addr.call(abi.encodeWithSelector(config.priceSig, amountOut));
            require(success, "ARMRouter: GET_TRADERATE_FAILED");

            // Decode the returned data to get the required input amount
            amountIn = abi.decode(data, (uint256));
        }
    }

    ////////////////////////////////////////////////////
    ///                 View Functions
    ////////////////////////////////////////////////////
    /// @notice Retrieves the ARM or Wrapper configuration for a given token pair.
    /// @param tokenA The address of the first token.
    /// @param tokenB The address of the second token.
    /// @return arm The configuration struct containing swap type, address, and function signatures.
    function getConfigFor(address tokenA, address tokenB) public view returns (Config memory arm) {
        // Fetch the ARM configuration for the token pair
        arm = configs[tokenA][tokenB];

        // Ensure the ARM configuration exists
        require(arm.addr != address(0), "ARMRouter: ARM_NOT_FOUND");
    }

    ////////////////////////////////////////////////////
    ///                 Owner Functions
    ////////////////////////////////////////////////////
    /// @notice Registers a new ARM or Wrapper configuration for a given token pair.
    /// @param tokenA The address of the first token.
    /// @param tokenB The address of the second token.
    /// @param swapType The type of swap (ARM or Wrapper).
    /// @param addr The address of the ARM or Wrapper contract.
    /// @param wrapSig The function signature for wrap/unwrap operations (only for Wrapper).
    /// @param priceSig The function signature for price queries on wrappers (only for Wrapper).
    function registerConfig(
        address tokenA,
        address tokenB,
        SwapType swapType,
        address addr,
        bytes4 wrapSig,
        bytes4 priceSig
    ) external {
        // Max approval for router to interact with ARMs
        IERC20(tokenA).approve(addr, type(uint256).max);
        IERC20(tokenB).approve(addr, type(uint256).max);

        // Store the ARM configuration
        configs[tokenA][tokenB] = Config({swapType: swapType, addr: addr, wrapSig: wrapSig, priceSig: priceSig});
    }
}
