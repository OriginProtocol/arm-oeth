// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "contracts/Interfaces.sol";

contract MockCurvePool {
    address public tokenIn;
    address public tokenOut;
    uint256 public dxUsed;
    uint256 public amountOut;

    function setSwap(address _tokenIn, address _tokenOut, uint256 _dxUsed, uint256 _amountOut) external {
        tokenIn = _tokenIn;
        tokenOut = _tokenOut;
        dxUsed = _dxUsed;
        amountOut = _amountOut;
    }

    function exchange(int128, int128, uint256, uint256 minDy) external returns (uint256) {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), dxUsed);
        require(amountOut >= minDy, "MockCurvePool: slippage");
        IERC20(tokenOut).transfer(msg.sender, amountOut);
        return amountOut;
    }
}
