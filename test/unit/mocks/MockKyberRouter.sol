// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "contracts/Interfaces.sol";

contract MockKyberRouter {
    function swapExactInput(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) external {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(msg.sender, amountOut);
    }

    function swapPartialInput(address tokenIn, address tokenOut, uint256 amountInUsed, uint256 amountOut) external {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountInUsed);
        IERC20(tokenOut).transfer(msg.sender, amountOut);
    }

    function revertSwap() external pure {
        revert("MockKyberRouter: revert");
    }
}
