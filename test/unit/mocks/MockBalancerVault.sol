// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "contracts/Interfaces.sol";
import {IBalancerVault} from "contracts/swappers/BalancerSwapTarget.sol";

contract MockBalancerVault is IBalancerVault {
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

    function swap(SingleSwap memory, FundManagement memory funds, uint256 limit, uint256)
        external
        payable
        override
        returns (uint256 amountCalculated)
    {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), dxUsed);
        require(amountOut >= limit, "MockBalancerVault: slippage");
        IERC20(tokenOut).transfer(funds.recipient, amountOut);
        return amountOut;
    }
}
