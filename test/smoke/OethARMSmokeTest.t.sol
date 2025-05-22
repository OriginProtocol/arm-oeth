// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {AbstractSmokeTest} from "./AbstractSmokeTest.sol";

import {IERC20} from "contracts/Interfaces.sol";
import {OethARM} from "contracts/OethARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

contract Fork_OethARM_Smoke_Test is AbstractSmokeTest {
    IERC20 BAD_TOKEN = IERC20(makeAddr("bad token"));

    IERC20 weth;
    IERC20 oeth;
    Proxy proxy;
    OethARM oethARM;
    address operator;

    function setUp() public {
        oeth = IERC20(resolver.resolve("OETH"));
        weth = IERC20(resolver.resolve("WETH"));
        operator = resolver.resolve("OPERATOR");

        vm.label(address(weth), "WETH");
        vm.label(address(oeth), "OETH");
        vm.label(address(operator), "OPERATOR");

        proxy = Proxy(payable(deployManager.getDeployment("OETH_ARM")));
        oethARM = OethARM(deployManager.getDeployment("OETH_ARM"));

        _dealWETH(address(oethARM), 100 ether);
        _dealOETH(address(oethARM), 100 ether);

        // Only fuzz from this address. Big speedup on fork.
        targetSender(address(this));
    }

    function test_swapExactTokensForTokens() external {
        _swapExactTokensForTokens(oeth, weth, 10 ether, 10 ether);
    }

    function test_swapTokensForExactTokens() external {
        _swapTokensForExactTokens(oeth, weth, 10 ether, 10 ether);
    }

    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, uint256 expectedOut)
        internal
    {
        if (inToken == weth) {
            _dealWETH(address(this), amountIn + 1000);
        } else {
            _dealOETH(address(this), amountIn + 1000);
        }
        // Approve the ARM to transfer the input token of the swap.
        inToken.approve(address(oethARM), amountIn);

        uint256 startIn = inToken.balanceOf(address(this));
        uint256 startOut = outToken.balanceOf(address(this));
        oethARM.swapExactTokensForTokens(inToken, outToken, amountIn, 0, address(this));
        assertEq(inToken.balanceOf(address(this)), startIn - amountIn, "In actual");
        assertEq(outToken.balanceOf(address(this)), startOut + expectedOut, "Out actual");
    }

    function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, uint256 expectedOut)
        internal
    {
        if (inToken == weth) {
            _dealWETH(address(this), amountIn + 1000);
        } else {
            _dealOETH(address(this), amountIn + 1000);
        }
        // Approve the ARM to transfer the input token of the swap.
        inToken.approve(address(oethARM), amountIn);

        uint256 startIn = inToken.balanceOf(address(this));

        oethARM.swapTokensForExactTokens(inToken, outToken, expectedOut, 3 * expectedOut, address(this));
        assertEq(inToken.balanceOf(address(this)), startIn - amountIn, "In actual");
        assertEq(outToken.balanceOf(address(this)), expectedOut, "Out actual");
    }

    function test_unauthorizedAccess() external {
        address RANDOM_ADDRESS = 0xfEEDBeef00000000000000000000000000000000;
        vm.startPrank(RANDOM_ADDRESS);

        // Proxy's restricted methods.
        vm.expectRevert("ARM: Only owner can call this function.");
        proxy.setOwner(RANDOM_ADDRESS);

        vm.expectRevert("ARM: Only owner can call this function.");
        proxy.initialize(address(this), address(this), "");

        vm.expectRevert("ARM: Only owner can call this function.");
        proxy.upgradeTo(address(this));

        vm.expectRevert("ARM: Only owner can call this function.");
        proxy.upgradeToAndCall(address(this), "");

        // Implementation's restricted methods.
        vm.expectRevert("ARM: Only owner can call this function.");
        oethARM.setOwner(RANDOM_ADDRESS);
    }

    function test_wrongInTokenExactIn() external {
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapExactTokensForTokens(BAD_TOKEN, oeth, 10 ether, 0, address(this));
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapExactTokensForTokens(BAD_TOKEN, weth, 10 ether, 0, address(this));
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapExactTokensForTokens(weth, weth, 10 ether, 0, address(this));
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapExactTokensForTokens(oeth, oeth, 10 ether, 0, address(this));
    }

    function test_wrongOutTokenExactIn() external {
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapTokensForExactTokens(weth, BAD_TOKEN, 10 ether, 10 ether, address(this));
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapTokensForExactTokens(oeth, BAD_TOKEN, 10 ether, 10 ether, address(this));
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapTokensForExactTokens(weth, weth, 10 ether, 10 ether, address(this));
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapTokensForExactTokens(oeth, oeth, 10 ether, 10 ether, address(this));
    }

    function test_wrongInTokenExactOut() external {
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapTokensForExactTokens(BAD_TOKEN, oeth, 10 ether, 10 ether, address(this));
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapTokensForExactTokens(BAD_TOKEN, weth, 10 ether, 10 ether, address(this));
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapTokensForExactTokens(weth, weth, 10 ether, 10 ether, address(this));
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapTokensForExactTokens(oeth, oeth, 10 ether, 10 ether, address(this));
    }

    function test_wrongOutTokenExactOut() external {
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapTokensForExactTokens(weth, BAD_TOKEN, 10 ether, 10 ether, address(this));
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapTokensForExactTokens(oeth, BAD_TOKEN, 10 ether, 10 ether, address(this));
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapTokensForExactTokens(weth, weth, 10 ether, 10 ether, address(this));
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapTokensForExactTokens(oeth, oeth, 10 ether, 10 ether, address(this));
    }

    function test_collectTokens() external {
        vm.startPrank(Mainnet.TIMELOCK);

        oethARM.transferToken(address(weth), address(this), weth.balanceOf(address(oethARM)));
        assertGt(weth.balanceOf(address(this)), 50 ether);
        assertEq(weth.balanceOf(address(oethARM)), 0);

        oethARM.transferToken(address(oeth), address(this), oeth.balanceOf(address(oethARM)));
        assertGt(oeth.balanceOf(address(this)), 50 ether);
        assertLt(oeth.balanceOf(address(oethARM)), 3);

        vm.stopPrank();
    }

    function _dealOETH(address to, uint256 amount) internal {
        vm.prank(0xDcEe70654261AF21C44c093C300eD3Bb97b78192);
        oeth.transfer(to, amount);
    }

    function _dealWETH(address to, uint256 amount) internal {
        deal(address(weth), to, amount);
    }

    /* Operator Tests */

    function test_setOperator() external {
        vm.prank(Mainnet.TIMELOCK);
        oethARM.setOperator(address(this));
        assertEq(oethARM.operator(), address(this));
    }

    function test_nonOwnerCannotSetOperator() external {
        vm.expectRevert("ARM: Only owner can call this function.");
        vm.prank(operator);
        oethARM.setOperator(operator);
    }
}
