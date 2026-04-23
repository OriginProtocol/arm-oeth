// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

import {KyberSwapTarget} from "contracts/swappers/KyberSwapTarget.sol";
import {MockKyberRouter} from "test/unit/mocks/MockKyberRouter.sol";

contract Unit_KyberSwapTarget_Test is Test {
    MockERC20 internal tokenIn;
    MockERC20 internal tokenOut;
    MockKyberRouter internal router;
    KyberSwapTarget internal target;

    function setUp() public {
        tokenIn = new MockERC20("Token In", "TIN", 18);
        tokenOut = new MockERC20("Token Out", "TOUT", 18);
        router = new MockKyberRouter();
        target = new KyberSwapTarget(address(router));
    }

    function test_RevertWhen_Constructor_Because_InvalidRouter() public {
        vm.expectRevert("KST: invalid router");
        new KyberSwapTarget(address(0));
    }

    function test_RevertWhen_Swap_Because_NoTokenOut() public {
        vm.expectRevert("KST: no tokenOut");
        target.swap(address(tokenIn), address(tokenOut), "");
    }

    function test_RevertWhen_Swap_Because_RouterFailed() public {
        bytes memory data = abi.encodeWithSelector(MockKyberRouter.revertSwap.selector);
        tokenOut.mint(address(target), 1 ether);

        vm.expectRevert("KST: kyber swap fail");
        target.swap(address(tokenIn), address(tokenOut), data);
    }

    function test_Swap_ReturnsTokenInToCaller() public {
        uint256 amountOut = 2 ether;
        uint256 amountIn = 1 ether;

        tokenOut.mint(address(target), amountOut);
        tokenIn.mint(address(router), amountIn);

        bytes memory data = abi.encodeWithSelector(
            MockKyberRouter.swapExactInput.selector, address(tokenOut), address(tokenIn), amountOut, amountIn
        );

        uint256 returnedAmountIn = target.swap(address(tokenIn), address(tokenOut), data);

        assertEq(returnedAmountIn, amountIn, "wrong amount in");
        assertEq(tokenIn.balanceOf(address(this)), amountIn, "wrong caller tokenIn balance");
        assertEq(tokenOut.balanceOf(address(this)), 0, "wrong caller tokenOut balance");
        assertEq(tokenOut.balanceOf(address(target)), 0, "wrong target tokenOut balance");
    }

    function test_Swap_ReturnsLeftoverTokenOutToCaller() public {
        uint256 amountOut = 2 ether;
        uint256 amountOutUsed = 1.5 ether;
        uint256 amountIn = 1 ether;

        tokenOut.mint(address(target), amountOut);
        tokenIn.mint(address(router), amountIn);

        bytes memory data = abi.encodeWithSelector(
            MockKyberRouter.swapPartialInput.selector, address(tokenOut), address(tokenIn), amountOutUsed, amountIn
        );

        target.swap(address(tokenIn), address(tokenOut), data);

        assertEq(tokenIn.balanceOf(address(this)), amountIn, "wrong caller tokenIn balance");
        assertEq(tokenOut.balanceOf(address(this)), amountOut - amountOutUsed, "wrong leftover tokenOut balance");
        assertEq(tokenOut.balanceOf(address(target)), 0, "wrong target tokenOut balance");
    }
}
