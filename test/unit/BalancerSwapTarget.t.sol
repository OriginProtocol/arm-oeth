// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

import {BalancerSwapTarget} from "contracts/swappers/BalancerSwapTarget.sol";
import {MockBalancerVault} from "test/unit/mocks/MockBalancerVault.sol";

contract Unit_BalancerSwapTarget_Test is Test {
    MockERC20 internal tokenIn;
    MockERC20 internal tokenOut;
    MockBalancerVault internal vault;
    BalancerSwapTarget internal target;

    function setUp() public {
        tokenIn = new MockERC20("Token In", "TIN", 18);
        tokenOut = new MockERC20("Token Out", "TOUT", 18);
        vault = new MockBalancerVault();
        target = new BalancerSwapTarget(address(vault));
    }

    function test_RevertWhen_Constructor_Because_InvalidVault() public {
        vm.expectRevert("BST: bad vault");
        new BalancerSwapTarget(address(0));
    }

    function test_RevertWhen_Swap_Because_NoTokenOut() public {
        vm.expectRevert("BST: no tokenOut");
        target.swap(address(tokenIn), address(tokenOut), bytes32(0), 0, "");
    }

    function test_RevertWhen_Swap_Because_Slippage() public {
        tokenOut.mint(address(target), 1 ether);
        vault.setSwap(address(tokenOut), address(tokenIn), 1 ether, 0.9 ether);

        vm.expectRevert("MockBalancerVault: slippage");
        target.swap(address(tokenIn), address(tokenOut), bytes32(uint256(1)), 1 ether, "");
    }

    function test_Swap_ReturnsTokenInToCaller() public {
        uint256 amountOut = 2 ether;
        uint256 amountIn = 1 ether;

        tokenOut.mint(address(target), amountOut);
        tokenIn.mint(address(vault), amountIn);
        vault.setSwap(address(tokenOut), address(tokenIn), amountOut, amountIn);

        uint256 returnedAmountIn = target.swap(address(tokenIn), address(tokenOut), bytes32(uint256(1)), amountIn, "");

        assertEq(returnedAmountIn, amountIn, "wrong amount in");
        assertEq(tokenIn.balanceOf(address(this)), amountIn, "wrong caller tokenIn");
        assertEq(tokenOut.balanceOf(address(this)), 0, "wrong caller tokenOut");
    }

    function test_Swap_ReturnsLeftoverTokenOutToCaller() public {
        uint256 amountOut = 2 ether;
        uint256 amountOutUsed = 1.5 ether;
        uint256 amountIn = 1 ether;

        tokenOut.mint(address(target), amountOut);
        tokenIn.mint(address(vault), amountIn);
        vault.setSwap(address(tokenOut), address(tokenIn), amountOutUsed, amountIn);

        target.swap(address(tokenIn), address(tokenOut), bytes32(uint256(1)), amountIn, "");

        assertEq(tokenIn.balanceOf(address(this)), amountIn, "wrong caller tokenIn");
        assertEq(tokenOut.balanceOf(address(this)), amountOut - amountOutUsed, "wrong leftover tokenOut");
    }
}
