// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

// Contract Imports
import {Ownable} from "contracts/Ownable.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";

// Library Imports
import {DynamicArrayLib} from "@solady/utils/DynamicArrayLib.sol";

// Interface Imports
import {IWETH} from "src/contracts/Interfaces.sol";
import {IERC20} from "src/contracts/Interfaces.sol";

/// @author Origin Protocol
/// @notice ARM Router contract for facilitating token swaps via ARMs and Wrappers.
contract ARMRouter is Ownable {
    using DynamicArrayLib for address[];
    using DynamicArrayLib for uint256[];

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
        require(deadline >= block.timestamp, "ARMRouter: EXPIRED");
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
        uint256 lastIndex;
        assembly {
            // lastIndex = amounts.length - 1
            lastIndex := sub(mload(amounts), 1)
        }
        require(amounts.get(lastIndex) >= amountOutMin, "ARMRouter: INSUFFICIENT_OUTPUT");
    }

    /// @notice Swaps as few input tokens as possible to receive an exact amount of output tokens, along the route determined by the path.
    /// @param amountOut The exact amount of output tokens to receive.
    /// @param amountInMax The maximum amount of input tokens that can be used for the swap.
    /// @param path An array of token addresses representing the swap path.
    /// @param to The address that will receive the output tokens.
    /// @param deadline The timestamp by which the transaction must be completed.
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        // Calculate the required input amounts for the desired output
        amounts = _getAmountsIn(amountOut, path);

        // Cache amounts[0] to save gas
        uint256 amount0 = amounts.get(0);
        // Ensure the required input does not exceed the maximum allowed
        require(amount0 <= amountInMax, "ARMRouter: EXCESSIVE_INPUT");

        // Transfer the input tokens from the sender to this contract
        IERC20(path[0]).transferFrom(msg.sender, address(this), amount0);

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
        uint256 lastIndex;
        assembly {
            // lastIndex = amounts.length - 1
            lastIndex := sub(mload(amounts), 1)
        }
        require(amounts.get(lastIndex) >= amountOutMin, "ARMRouter: INSUFFICIENT_OUTPUT");
    }

    /// @notice Swaps an exact amount of input tokens for as much ETH as possible, along the route determined by the path.
    /// @param amountIn The exact amount of input tokens to swap.
    /// @param amountOutMin The minimum amount of ETH that must be received for the transaction not to revert.
    /// @param path An array of token addresses representing the swap path.
    /// @param to The address that will receive the ETH.
    /// @param deadline The timestamp by which the transaction must be completed.
    /// @return amounts An array of token amounts for each step in the swap path.
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        // Cache last index in list to save gas, path and amounts lengths are the same
        // Done in 2 operations to save gas
        uint256 lenMinusOne = path.length;
        assembly {
            lenMinusOne := sub(lenMinusOne, 1)
        }

        // Ensure the last token in the path is WETH
        require(path[lenMinusOne] == address(WETH), "ARMRouter: INVALID_PATH");

        // Transfer the input tokens from the sender to this contract
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        // Perform the swaps along the path
        amounts = _swapExactTokenFor(amountIn, path, address(this));

        // Ensure the output amount meets the minimum requirement
        require(amounts.get(lenMinusOne) >= amountOutMin, "ARMRouter: INSUFFICIENT_OUTPUT");

        // Unwrap WETH to ETH and transfer to the recipient
        WETH.withdraw(amounts.get(lenMinusOne));
        payable(to).transfer(amounts.get(lenMinusOne));
    }

    /// @notice Swaps as few ETH as possible to receive an exact amount of output tokens, along the route determined by the path.
    /// @param amountOut The exact amount of output tokens to receive.
    /// @param path An array of token addresses representing the swap path.
    /// @param to The address that will receive the output tokens.
    /// @param deadline The timestamp by which the transaction must be completed.
    /// @return amounts An array of token amounts for each step in the swap path.
    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        // Ensure the first token in the path is WETH
        require(path[0] == address(WETH), "ARMRouter: INVALID_PATH");

        // Calculate the required input amounts for the desired output
        amounts = _getAmountsIn(amountOut, path);

        // Cache amounts[0] to save gas
        uint256 amount0 = amounts.get(0);

        // Ensure the required input does not exceed the sent ETH
        require(amount0 <= msg.value, "ARMRouter: EXCESSIVE_INPUT");

        // Wrap ETH to WETH
        WETH.deposit{value: amount0}();

        // Perform the swaps along the path
        _swapsForExactTokens(amounts, path, to);

        // Refund any excess ETH to the sender
        if (msg.value > amount0) payable(msg.sender).transfer(msg.value - amount0);
    }

    /// @notice Swaps as few input tokens as possible to receive an exact amount of ETH, along the route determined by the path.
    /// @param amountOut The exact amount of ETH to receive.
    /// @param amountInMax The maximum amount of input tokens that can be used for the swap.
    /// @param path An array of token addresses representing the swap path.
    /// @param to The address that will receive the ETH.
    /// @param deadline The timestamp by which the transaction must be completed.
    /// @return amounts An array of token amounts for each step in the swap path.
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        // Cache last index in list to save gas, path and amounts lengths are the same
        // Done in 2 operations to save gas
        uint256 lenMinusOne = path.length;
        assembly {
            lenMinusOne := sub(lenMinusOne, 1)
        }
        // Ensure the last token in the path is WETH
        require(path[lenMinusOne] == address(WETH), "ARMRouter: INVALID_PATH");

        // Calculate the required input amounts for the desired output
        amounts = _getAmountsIn(amountOut, path);

        // Cache amounts[0] to save gas
        uint256 amount0 = amounts.get(0);
        // Ensure the required input does not exceed the maximum allowed
        require(amount0 <= amountInMax, "ARMRouter: EXCESSIVE_INPUT");

        // Transfer the input tokens from the sender to this contract
        IERC20(path[0]).transferFrom(msg.sender, address(this), amount0);

        // Perform the swaps along the path
        _swapsForExactTokens(amounts, path, address(this));

        // Cache last amount to save gas
        uint256 lastAmount = amounts.get(lenMinusOne);
        // Unwrap WETH to ETH and transfer to the recipient
        WETH.withdraw(lastAmount);
        payable(to).transfer(lastAmount);
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
        // Cache length to save gas
        uint256 len = path.length;

        // Initialize the amounts array
        amounts = DynamicArrayLib.malloc(len);
        amounts.set(0, amountIn);

        // Cache next index to save gas
        uint256 _next;
        // Cache length minus two to save gas
        uint256 lenMinusTwo;
        assembly {
            // lenMinusTwo = len - 2
            lenMinusTwo := sub(len, 2)
        }
        // Perform the swaps along the path
        for (uint256 i; i < len - 1; i++) {
            // Next token index
            assembly {
                // _next += 1
                _next := add(_next, 1)
            }

            // Cache token addresses to save gas
            address tokenA = path[i];
            address tokenB = path[_next];

            // Get ARM or Wrapper config
            Config memory config = getConfigFor(tokenA, tokenB);

            if (config.swapType == SwapType.ARM) {
                // Determine receiver address
                address receiver = i < lenMinusTwo ? address(this) : to;

                // Call the ARM contract's swap function
                uint256[] memory obtained = AbstractARM(config.addr)
                    .swapExactTokensForTokens(IERC20(tokenA), IERC20(tokenB), amounts.get(i), 0, receiver);

                // Perform the ARM swap
                amounts[_next] = obtained.get(1);
            } else {
                // Call the Wrapper contract's wrap/unwrap function
                (bool success, bytes memory data) =
                    config.addr.call(abi.encodeWithSelector(config.wrapSig, amounts.get(i)));

                // Ensure the wrap/unwrap was successful
                require(success, "ARMRouter: WRAP_UNWRAP_FAILED");

                // It's a wrap/unwrap operation
                amounts.set(_next, abi.decode(data, (uint256)));

                // If this is the last swap, transfer to the recipient
                if (i == lenMinusTwo) IERC20(tokenB).transfer(to, amounts.get(_next));
            }
        }
    }

    /// @notice Internal function to perform swaps for exact output amounts along the specified path.
    /// @param amounts The array of token amounts for each step in the swap path.
    /// @param path The swap path as an array of token addresses.
    /// @param to The address that will receive the output tokens.
    function _swapsForExactTokens(uint256[] memory amounts, address[] memory path, address to) internal {
        // Cache length to save gas
        uint256 len = path.length;
        // Cache next index to save gas
        uint256 _next;
        // Cache length minus two to save gas
        uint256 lenMinusTwo;
        assembly {
            // lenMinusTwo = len - 2
            lenMinusTwo := sub(len, 2)
        }
        for (uint256 i; i < len - 1; i++) {
            // Next token index
            assembly {
                // _next += 1
                _next := add(_next, 1)
            }

            // Cache token addresses to save gas
            address tokenA = path[i];
            address tokenB = path[_next];

            // Get ARM or Wrapper config
            Config memory config = getConfigFor(tokenA, tokenB);

            if (config.swapType == SwapType.ARM) {
                // Determine receiver address
                address receiver = i < lenMinusTwo ? address(this) : to;

                // Perform the ARM swap
                AbstractARM(config.addr)
                    .swapTokensForExactTokens(IERC20(tokenA), IERC20(tokenB), amounts[_next], amounts[i], receiver);
            } else {
                // Call the Wrapper contract's wrap/unwrap function
                (bool success,) = config.addr.call(abi.encodeWithSelector(config.wrapSig, amounts.get(i)));

                // Ensure the wrap/unwrap was successful
                require(success, "ARMRouter: WRAP_UNWRAP_FAILED");

                // If this is the last swap, transfer to the recipient
                if (i == lenMinusTwo) IERC20(tokenB).transfer(to, amounts.get(_next));
            }
        }
    }

    /// @notice Calculates the required input amounts for a desired output amount along the specified path.
    /// @param amountOut The desired output amount of the final token in the path.
    /// @param path The swap path as an array of token addresses.
    /// @return amounts An array of token amounts for each step in the swap path.
    function _getAmountsIn(uint256 amountOut, address[] memory path) internal returns (uint256[] memory amounts) {
        // Cache length to save gas
        uint256 len = path.length;
        // Cache length minus one to save gas, in 2 operations to safe gas
        uint256 lenMinusOne = len;
        assembly {
            // lenMinusOne -= 1
            lenMinusOne := sub(lenMinusOne, 1)
        }
        // Ensure the path has at least two tokens
        require(lenMinusOne > 0, "ARMRouter: INVALID_PATH");

        // Initialize the amounts array
        amounts = DynamicArrayLib.malloc(len);
        amounts.set(lenMinusOne, amountOut);

        // Cache next index to save gas
        uint256 _next = lenMinusOne;
        // Calculate required input amounts in reverse order
        for (uint256 i = lenMinusOne; i > 0; i--) {
            // Next token index
            assembly {
                // _next -= 1
                _next := sub(_next, 1)
            }
            amounts.set(_next, _getAmountIn(amounts.get(i), path[_next], path[i]));
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
            require(success, "ARMRouter: GET_TRADERATE_FAIL");

            // Decode the returned data to get the required input amount
            amountIn = abi.decode(data, (uint256));
            // Add 1 to account for rounding errors
            assembly {
                // amountIn += 1
                amountIn := add(amountIn, 1)
            }
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
        require(arm.addr != address(0), "ARMRouter: PATH_NOT_FOUND");
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
    ) external onlyOwner {
        // Max approval for router to interact with ARMs
        IERC20(tokenA).approve(addr, type(uint256).max);

        // Store the ARM configuration
        configs[tokenA][tokenB] = Config({swapType: swapType, addr: addr, wrapSig: wrapSig, priceSig: priceSig});
    }

    receive() external payable {}
}
