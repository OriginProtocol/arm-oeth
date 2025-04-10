// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {AbstractARM} from "./AbstractARM.sol";
import {IERC20} from "./Interfaces.sol";

abstract contract PeggedARM is AbstractARM {
    /// @notice If true, the ARM contract can swap in both directions between token0 and token1.
    bool public immutable bothDirections;

    constructor(bool _bothDirections) {
        bothDirections = _bothDirections;
    }

    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, address to)
        internal
        override
        returns (uint256 amountOut)
    {
        return _swap(inToken, outToken, amountIn, to);
    }

    function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 amountOut, address to)
        internal
        override
        returns (uint256 amountIn)
    {
        return _swap(inToken, outToken, amountOut, to);
    }

    function _swap(IERC20 inToken, IERC20 outToken, uint256 amount, address to) internal returns (uint256) {
        if (bothDirections) {
            require(
                inToken == token0 && outToken == token1 || inToken == token1 && outToken == token0, "ARM: Invalid swap"
            );
        } else {
            require(inToken == token0 && outToken == token1, "ARM: Invalid swap");
        }

        // Transfer the input tokens from the caller to this ARM contract
        require(inToken.transferFrom(msg.sender, address(this), amount), "failed transfer in");

        // Transfer the same amount of output tokens to the recipient
        require(outToken.transfer(to, amount), "failed transfer out");

        // 1:1 swaps so the exact amount is returned as the calculated amount
        return amount;
    }
}
