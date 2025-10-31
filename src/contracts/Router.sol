// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC20} from "src/contracts/Interfaces.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";

contract ARMRouter {
    ////////////////////////////////////////////////////
    ///                 Constants and Immutables
    ////////////////////////////////////////////////////
    uint256 public constant PRICE_SCALE = 1e36;

    ////////////////////////////////////////////////////
    ///                 State Variables
    ////////////////////////////////////////////////////
    mapping(address => mapping(address => address)) internal arms;

    ////////////////////////////////////////////////////
    ///                 Modifiers
    ////////////////////////////////////////////////////
    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
        _;
    }

    ////////////////////////////////////////////////////
    ///                 Swap Functions
    ////////////////////////////////////////////////////
    /// @notice Swaps an exact amount of input tokens for as many output tokens as possible, along the route determined by the path.
    /// @param amountIn The exact amount of input tokens to swap.
    /// @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
    /// @param path An array of token addresses representing the swap path.
    /// @param to The address that will receive the output tokens.
    /// @param deadline The timestamp by which the transaction must be completed.
    /// @return amounts An array of token amounts for each step in the swap path.
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        // Get output amounts for the swap
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "ARMRouter: INSUFFICIENT_OUTPUT_AMOUNT");

        // Transfer the input tokens from the sender to this contract
        IERC20(path[0]).transferFrom(msg.sender, address(this), amounts[0]);

        // Perform the swaps along the path
        uint256 len = path.length;
        for (uint256 i; i < len - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            address arm = getArmFor(input, output);

            AbstractARM(arm)
                .swapExactTokensForTokens(
                    IERC20(input), IERC20(output), amounts[i], amounts[i + 1], i < len - 2 ? address(this) : to
                );
        }
    }

    ////////////////////////////////////////////////////
    ///                 Helpers Functions
    ////////////////////////////////////////////////////
    /// @notice Given an input amount of an asset and a swap path, returns the maximum output amounts of each asset in the path.
    /// @param amountIn The exact amount of input tokens to swap.
    /// @param path An array of token addresses representing the swap path.
    /// @return amounts An array of token amounts for each step in the swap path.
    function getAmountsOut(uint256 amountIn, address[] memory path) internal view returns (uint256[] memory amounts) {
        uint256 len = path.length;
        require(len >= 2, "ARMLibrary: INVALID_PATH");

        amounts = new uint256[](len);
        amounts[0] = amountIn;

        for (uint256 i; i < len - 1; i++) {
            // Get traderate from ARM
            uint256 traderate = getTraderate(path[i], path[i + 1]);

            // Calculate output amount based on traderate
            amounts[i + 1] = (amounts[i] * traderate) / PRICE_SCALE;
        }
    }

    /// @notice Given a pair of tokens, returns the current traderate for the swap.
    /// @param tokenA The address of the first token i.e. the input token.
    /// @param tokenB The address of the second token i.e. the output token.
    /// @return traderate The current traderate for the swap.
    function getTraderate(address tokenA, address tokenB) internal view returns (uint256 traderate) {
        address arm = getArmFor(tokenA, tokenB);
        address token0 = address(AbstractARM(arm).token0());
        traderate = tokenA == address(token0) ? AbstractARM(arm).traderate0() : AbstractARM(arm).traderate1();
    }

    /// @notice Given a pair of tokens, returns the address of the associated ARM.
    /// @param tokenA The address of the first token.
    /// @param tokenB The address of the second token.
    /// @return arm The address of the associated ARM.
    function getArmFor(address tokenA, address tokenB) internal view returns (address arm) {
        arm = arms[tokenA][tokenB];
        require(arm != address(0), "ARMRouter: ARM_NOT_FOUND");
    }
}
