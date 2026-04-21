// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20 as IERC20OZ} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICurvePool {
    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy) external payable returns (uint256 amountOut);
}

/**
 * @title CurveSwapTarget
 * @notice Swap callback target for ARM market swaps via a Curve pool.
 */
contract CurveSwapTarget {
    using SafeERC20 for IERC20OZ;

    address public immutable pool;

    event CurveSwap(address indexed caller, address indexed tokenIn, address indexed tokenOut, uint256 amountIn);

    constructor(address _pool) {
        require(_pool != address(0), "CST: bad pool");
        pool = _pool;
    }

    function swap(address tokenIn, address tokenOut, int128 i, int128 j, uint256 minDy)
        external
        returns (uint256 amountIn)
    {
        uint256 amountOut = IERC20OZ(tokenOut).balanceOf(address(this));
        require(amountOut > 0, "CST: no tokenOut");

        IERC20OZ(tokenOut).forceApprove(pool, amountOut);

        ICurvePool(pool).exchange(i, j, amountOut, minDy);

        IERC20OZ(tokenOut).forceApprove(pool, 0);

        amountIn = IERC20OZ(tokenIn).balanceOf(address(this));
        if (amountIn > 0) IERC20OZ(tokenIn).safeTransfer(msg.sender, amountIn);

        uint256 leftoverTokenOut = IERC20OZ(tokenOut).balanceOf(address(this));
        if (leftoverTokenOut > 0) IERC20OZ(tokenOut).safeTransfer(msg.sender, leftoverTokenOut);

        emit CurveSwap(msg.sender, tokenIn, tokenOut, amountIn);
    }
}
