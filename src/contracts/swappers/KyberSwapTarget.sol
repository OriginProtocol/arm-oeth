// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20 as IERC20OZ} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title KyberSwapTarget
 * @notice Swap callback target for ARM market swaps via Kyber's router.
 */
contract KyberSwapTarget {
    using SafeERC20 for IERC20OZ;

    /// @notice Kyber MetaAggregationRouterV2.
    address public immutable router;

    event KyberSwap(address indexed caller, address indexed tokenIn, address indexed tokenOut, uint256 amountIn);

    constructor(address _router) {
        require(_router != address(0), "KST: invalid router");
        router = _router;
    }

    /**
     * @notice Swap tokenOut held by this contract via Kyber and return tokenIn plus any leftover tokenOut
     * back to the caller.
     * @param tokenIn Token that should be returned to the caller after the swap.
     * @param tokenOut Token that has already been transferred into this contract by the ARM.
     * @param data Encoded calldata for the Kyber router.
     * @return amountIn Amount of tokenIn returned to the caller.
     */
    function swap(address tokenIn, address tokenOut, bytes calldata data) external returns (uint256 amountIn) {
        uint256 amountOut = IERC20OZ(tokenOut).balanceOf(address(this));
        require(amountOut > 0, "KST: no tokenOut");

        IERC20OZ(tokenOut).forceApprove(router, amountOut);

        (bool success,) = router.call(data);
        require(success, "KST: kyber swap fail");

        IERC20OZ(tokenOut).forceApprove(router, 0);

        amountIn = IERC20OZ(tokenIn).balanceOf(address(this));
        if (amountIn > 0) IERC20OZ(tokenIn).safeTransfer(msg.sender, amountIn);

        uint256 leftoverTokenOut = IERC20OZ(tokenOut).balanceOf(address(this));
        if (leftoverTokenOut > 0) IERC20OZ(tokenOut).safeTransfer(msg.sender, leftoverTokenOut);

        emit KyberSwap(msg.sender, tokenIn, tokenOut, amountIn);
    }
}
