// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

import {CurveSwapTarget} from "contracts/swappers/CurveSwapTarget.sol";
import {MockCurvePool} from "test/unit/mocks/MockCurvePool.sol";

contract Unit_CurveSwapTarget_Test is Test {
    MockERC20 internal tokenIn;
    MockERC20 internal tokenOut;
    MockCurvePool internal pool;
    CurveSwapTarget internal target;

    function setUp() public {
        tokenIn = new MockERC20("Token In", "TIN", 18);
        tokenOut = new MockERC20("Token Out", "TOUT", 18);
        pool = new MockCurvePool();
        target = new CurveSwapTarget(address(pool));
    }

    function test_RevertWhen_Constructor_Because_InvalidPool() public {
        vm.expectRevert("CST: bad pool");
        new CurveSwapTarget(address(0));
    }

    function test_RevertWhen_Swap_Because_NoTokenOut() public {
        vm.expectRevert("CST: no tokenOut");
        target.swap(address(tokenIn), address(tokenOut), 0, 1, 0);
    }

    function test_Swap_ReturnsTokenInToCaller() public {
        uint256 amountOut = 2 ether;
        uint256 amountIn = 1 ether;

        tokenOut.mint(address(target), amountOut);
        tokenIn.mint(address(pool), amountIn);
        pool.setSwap(address(tokenOut), address(tokenIn), amountOut, amountIn);

        uint256 returnedAmountIn = target.swap(address(tokenIn), address(tokenOut), 0, 1, amountIn);

        assertEq(returnedAmountIn, amountIn, "wrong amount in");
        assertEq(tokenIn.balanceOf(address(this)), amountIn, "wrong caller tokenIn");
        assertEq(tokenOut.balanceOf(address(this)), 0, "wrong caller tokenOut");
    }

    function test_Swap_ReturnsLeftoverTokenOutToCaller() public {
        uint256 amountOut = 2 ether;
        uint256 amountOutUsed = 1.5 ether;
        uint256 amountIn = 1 ether;

        tokenOut.mint(address(target), amountOut);
        tokenIn.mint(address(pool), amountIn);
        pool.setSwap(address(tokenOut), address(tokenIn), amountOutUsed, amountIn);

        target.swap(address(tokenIn), address(tokenOut), 0, 1, amountIn);

        assertEq(tokenIn.balanceOf(address(this)), amountIn, "wrong caller tokenIn");
        assertEq(tokenOut.balanceOf(address(this)), amountOut - amountOutUsed, "wrong leftover tokenOut");
    }
}
