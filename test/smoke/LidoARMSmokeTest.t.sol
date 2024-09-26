// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {AbstractSmokeTest} from "./AbstractSmokeTest.sol";

import {IERC20} from "contracts/Interfaces.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {console} from "forge-std/console.sol";

contract Fork_LidoARM_Smoke_Test is AbstractSmokeTest {
    IERC20 BAD_TOKEN = IERC20(makeAddr("bad token"));

    IERC20 weth;
    IERC20 steth;
    Proxy proxy;
    LidoARM lidoARM;
    address operator;

    function setUp() public {
        weth = IERC20(resolver.resolve("WETH"));
        steth = IERC20(resolver.resolve("STETH"));
        operator = resolver.resolve("OPERATOR");

        vm.label(address(weth), "WETH");
        vm.label(address(steth), "stETH");
        vm.label(address(operator), "OPERATOR");

        proxy = Proxy(deployManager.getDeployment("LIDO_ARM"));
        lidoARM = LidoARM(payable(deployManager.getDeployment("LIDO_ARM")));

        // Only fuzz from this address. Big speedup on fork.
        targetSender(address(this));
    }

    function test_initialConfig() external view {
        assertEq(lidoARM.name(), "Lido ARM", "Name");
        assertEq(lidoARM.symbol(), "ARM-ST", "Symbol");
        assertEq(lidoARM.owner(), Mainnet.GOV_MULTISIG, "Owner");
        assertEq(lidoARM.operator(), Mainnet.ARM_RELAYER, "Operator");
        assertEq(lidoARM.feeCollector(), Mainnet.ARM_BUYBACK, "Fee collector");
        assertEq((100 * uint256(lidoARM.fee())) / lidoARM.FEE_SCALE(), 15, "Performance fee as a percentage");
        assertEq(lidoARM.feesAccrued(), 0, "Fees accrued");
        // Some dust stETH is left in AMM v1 when stETH is transferred to the Treasury.
        assertEq(lidoARM.totalAssets(), 1e12 + 1, "Total assets");
        assertEq(lidoARM.lastTotalAssets(), 1e12 + 1, "Last total assets");
        assertEq(lidoARM.totalSupply(), 1e12, "Total supply");
        assertEq(weth.balanceOf(address(lidoARM)), 1e12, "WETH balance");
    }

    function test_swapExactTokensForTokens() external {
        _swapExactTokensForTokens(steth, weth, 10 ether, 10 ether);
    }

    function test_swapTokensForExactTokens() external {
        _swapTokensForExactTokens(steth, weth, 10 ether, 10 ether);
    }

    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, uint256 expectedOut)
        internal
    {
        _dealWETH(address(lidoARM), 100 ether);
        _dealStETH(address(lidoARM), 100 ether);
        if (inToken == weth) {
            _dealWETH(address(this), amountIn + 1000);
        } else {
            _dealStETH(address(this), amountIn + 1000);
        }
        // Approve the ARM to transfer the input token of the swap.
        inToken.approve(address(lidoARM), amountIn);

        uint256 startIn = inToken.balanceOf(address(this));
        uint256 startOut = outToken.balanceOf(address(this));

        lidoARM.swapExactTokensForTokens(inToken, outToken, amountIn, 0, address(this));

        assertApproxEqAbs(inToken.balanceOf(address(this)), startIn - amountIn, 2, "In actual");
        assertEq(outToken.balanceOf(address(this)), startOut + expectedOut, "Out actual");
    }

    function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, uint256 expectedOut)
        internal
    {
        _dealWETH(address(lidoARM), 100 ether);
        _dealStETH(address(lidoARM), 100 ether);
        if (inToken == weth) {
            _dealWETH(address(this), amountIn + 1000);
        } else {
            _dealStETH(address(this), amountIn + 1000);
        }
        // Approve the ARM to transfer the input token of the swap.
        inToken.approve(address(lidoARM), amountIn + 10000);
        console.log("Approved Lido ARM to spend %d", inToken.allowance(address(this), address(lidoARM)));
        console.log("In token balance: %d", inToken.balanceOf(address(this)));

        uint256 startIn = inToken.balanceOf(address(this));

        lidoARM.swapTokensForExactTokens(inToken, outToken, expectedOut, 3 * expectedOut, address(this));

        assertApproxEqAbs(inToken.balanceOf(address(this)), startIn - amountIn, 2, "In actual");
        assertEq(outToken.balanceOf(address(this)), expectedOut, "Out actual");
    }

    function test_proxy_unauthorizedAccess() external {
        address RANDOM_ADDRESS = 0xfEEDBeef00000000000000000000000000000000;
        vm.startPrank(RANDOM_ADDRESS);

        // Proxy's restricted methods.
        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.setOwner(RANDOM_ADDRESS);

        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.initialize(address(this), address(this), "");

        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.upgradeTo(address(this));

        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.upgradeToAndCall(address(this), "");

        // Implementation's restricted methods.
        vm.expectRevert("OSwap: Only owner can call this function.");
        lidoARM.setOwner(RANDOM_ADDRESS);
    }

    function _dealStETH(address to, uint256 amount) internal {
        vm.prank(0xEB9c1CE881F0bDB25EAc4D74FccbAcF4Dd81020a);
        steth.transfer(to, amount + 2);
    }

    function _dealWETH(address to, uint256 amount) internal {
        deal(address(weth), to, amount);
    }

    /* Operator Tests */

    function test_setOperator() external {
        vm.prank(Mainnet.GOV_MULTISIG);
        lidoARM.setOperator(address(this));
        assertEq(lidoARM.operator(), address(this));
    }

    function test_nonOwnerCannotSetOperator() external {
        vm.expectRevert("ARM: Only owner can call this function.");
        vm.prank(operator);
        lidoARM.setOperator(operator);
    }
}
