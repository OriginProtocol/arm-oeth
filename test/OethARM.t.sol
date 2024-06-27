// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {IERC20} from "contracts/Interfaces.sol";
import {OEthARM} from "contracts/OethARM.sol";
import {Proxy} from "contracts/Proxy.sol";

contract OethARMTest is Test {
    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 oeth = IERC20(0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3);
    IERC20 BAD_TOKEN = IERC20(makeAddr("bad token"));

    address operator = makeAddr("operator");

    Proxy proxy;
    OEthARM oethARM;

    function setUp() public {
        OEthARM implementation = new OEthARM();
        proxy = new Proxy();
        proxy.initialize(address(implementation), address(this), "");
        oethARM = OEthARM(address(proxy));

        _dealWETH(address(oethARM), 100 ether);
        _dealOETH(address(oethARM), 100 ether);

        // Set operator
        oethARM.setOperator(operator);
        vm.label(address(weth), "WETH");
        vm.label(address(oeth), "OETH");

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
        oethARM.transferToken(address(weth), address(this), weth.balanceOf(address(oethARM)));
        assertGt(weth.balanceOf(address(this)), 50 ether);
        assertEq(weth.balanceOf(address(oethARM)), 0);

        oethARM.transferToken(address(oeth), address(this), oeth.balanceOf(address(oethARM)));
        assertGt(oeth.balanceOf(address(this)), 50 ether);
        assertLt(oeth.balanceOf(address(oethARM)), 3);
    }

    function _dealOETH(address to, uint256 amount) internal {
        vm.prank(0x8E02247D3eE0E6153495c971FFd45Aa131f4D7cB);
        oeth.transfer(to, amount);
    }

    function _dealWETH(address to, uint256 amount) internal {
        deal(address(weth), to, amount);
    }

    /* Operator Tests */

    function test_setOperator() external {
        oethARM.setOperator(address(this));
        assertEq(oethARM.operator(), address(this));
    }

    function test_nonOwnerCannotSetOperator() external {
        vm.expectRevert("ARM: Only owner can call this function.");
        vm.prank(operator);
        oethARM.setOperator(operator);
    }
}
