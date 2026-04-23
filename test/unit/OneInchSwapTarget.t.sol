// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

import {OneInchSwapTarget} from "contracts/swappers/OneInchSwapTarget.sol";
import {MockOneInchRouter} from "test/unit/mocks/MockOneInchRouter.sol";

contract Unit_OneInchSwapTarget_Test is Test {
    MockERC20 internal tokenIn;
    MockERC20 internal tokenOut;
    MockOneInchRouter internal router;
    OneInchSwapTarget internal target;

    function setUp() public {
        tokenIn = new MockERC20("Token In", "TIN", 18);
        tokenOut = new MockERC20("Token Out", "TOUT", 18);
        router = new MockOneInchRouter();
        target = new OneInchSwapTarget(address(router));
    }

    function test_RevertWhen_Constructor_Because_InvalidRouter() public {
        vm.expectRevert("OST: bad router");
        new OneInchSwapTarget(address(0));
    }

    function test_RevertWhen_Swap_Because_NoTokenOut() public {
        vm.expectRevert("OST: no tokenOut");
        target.swap(address(tokenIn), address(tokenOut), "");
    }

    function test_RevertWhen_Swap_Because_RouterFailed() public {
        tokenOut.mint(address(target), 1 ether);
        bytes memory data = abi.encodeWithSelector(MockOneInchRouter.revertSwap.selector);

        vm.expectRevert("OST: 1inch fail");
        target.swap(address(tokenIn), address(tokenOut), data);
    }

    function test_Swap_ReturnsTokenInToCaller() public {
        uint256 amountOut = 2 ether;
        uint256 amountIn = 1 ether;

        tokenOut.mint(address(target), amountOut);
        tokenIn.mint(address(router), amountIn);

        bytes memory data = abi.encodeWithSelector(
            MockOneInchRouter.swapExactInput.selector, address(tokenOut), address(tokenIn), amountOut, amountIn
        );

        uint256 returnedAmountIn = target.swap(address(tokenIn), address(tokenOut), data);

        assertEq(returnedAmountIn, amountIn, "wrong amount in");
        assertEq(tokenIn.balanceOf(address(this)), amountIn, "wrong caller tokenIn");
        assertEq(tokenOut.balanceOf(address(this)), 0, "wrong caller tokenOut");
    }

    function test_Swap_ReturnsLeftoverTokenOutToCaller() public {
        uint256 amountOut = 2 ether;
        uint256 amountOutUsed = 1.5 ether;
        uint256 amountIn = 1 ether;

        tokenOut.mint(address(target), amountOut);
        tokenIn.mint(address(router), amountIn);

        bytes memory data = abi.encodeWithSelector(
            MockOneInchRouter.swapPartialInput.selector, address(tokenOut), address(tokenIn), amountOutUsed, amountIn
        );

        target.swap(address(tokenIn), address(tokenOut), data);

        assertEq(tokenIn.balanceOf(address(this)), amountIn, "wrong caller tokenIn");
        assertEq(tokenOut.balanceOf(address(this)), amountOut - amountOutUsed, "wrong leftover tokenOut");
    }
}
