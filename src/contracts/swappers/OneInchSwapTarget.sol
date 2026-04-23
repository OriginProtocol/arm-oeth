// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20 as IERC20OZ} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title OneInchSwapTarget
 * @notice Swap callback target for ARM market swaps via a 1inch router.
 */
contract OneInchSwapTarget {
    using SafeERC20 for IERC20OZ;

    address public immutable router;

    event OneInchSwap(address indexed caller, address indexed tokenIn, address indexed tokenOut, uint256 amountIn);

    constructor(address _router) {
        require(_router != address(0), "OST: bad router");
        router = _router;
    }

    function swap(address tokenIn, address tokenOut, bytes calldata data) external returns (uint256 amountIn) {
        uint256 amountOut = IERC20OZ(tokenOut).balanceOf(address(this));
        require(amountOut > 0, "OST: no tokenOut");

        IERC20OZ(tokenOut).forceApprove(router, amountOut);

        (bool success,) = router.call(data);
        require(success, "OST: 1inch fail");

        IERC20OZ(tokenOut).forceApprove(router, 0);

        amountIn = IERC20OZ(tokenIn).balanceOf(address(this));
        if (amountIn > 0) IERC20OZ(tokenIn).safeTransfer(msg.sender, amountIn);

        uint256 leftoverTokenOut = IERC20OZ(tokenOut).balanceOf(address(this));
        if (leftoverTokenOut > 0) IERC20OZ(tokenOut).safeTransfer(msg.sender, leftoverTokenOut);

        emit OneInchSwap(msg.sender, tokenIn, tokenOut, amountIn);
    }
}
