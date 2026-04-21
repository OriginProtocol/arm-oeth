// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20 as IERC20OZ} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBalancerVault {
    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address recipient;
        bool toInternalBalance;
    }

    function swap(SingleSwap memory singleSwap, FundManagement memory funds, uint256 limit, uint256 deadline)
        external
        payable
        returns (uint256 amountCalculated);
}

/**
 * @title BalancerSwapTarget
 * @notice Swap callback target for ARM market swaps via a Balancer Vault.
 */
contract BalancerSwapTarget {
    using SafeERC20 for IERC20OZ;

    address public immutable vault;

    event BalancerSwap(address indexed caller, address indexed tokenIn, address indexed tokenOut, uint256 amountIn);

    constructor(address _vault) {
        require(_vault != address(0), "BST: bad vault");
        vault = _vault;
    }

    function swap(address tokenIn, address tokenOut, bytes32 poolId, uint256 minAmountIn, bytes calldata userData)
        external
        returns (uint256 amountIn)
    {
        uint256 amountOut = IERC20OZ(tokenOut).balanceOf(address(this));
        require(amountOut > 0, "BST: no tokenOut");

        IERC20OZ(tokenOut).forceApprove(vault, amountOut);

        IBalancerVault(vault).swap(
            IBalancerVault.SingleSwap({
                poolId: poolId,
                kind: IBalancerVault.SwapKind.GIVEN_IN,
                assetIn: tokenOut,
                assetOut: tokenIn,
                amount: amountOut,
                userData: userData
            }),
            IBalancerVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            }),
            minAmountIn,
            block.timestamp
        );

        IERC20OZ(tokenOut).forceApprove(vault, 0);

        amountIn = IERC20OZ(tokenIn).balanceOf(address(this));
        if (amountIn > 0) IERC20OZ(tokenIn).safeTransfer(msg.sender, amountIn);

        uint256 leftoverTokenOut = IERC20OZ(tokenOut).balanceOf(address(this));
        if (leftoverTokenOut > 0) IERC20OZ(tokenOut).safeTransfer(msg.sender, leftoverTokenOut);

        emit BalancerSwap(msg.sender, tokenIn, tokenOut, amountIn);
    }
}
