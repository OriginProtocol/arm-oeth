// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";

contract Unit_Concrete_OriginARM_SwapLiquidityLimits_Test_ is Unit_Shared_Test {
    function test_SwapExactTokensForTokens_BuySide_ConsumesBaseAssetCap() public {
        uint256 buyCap = 3 ether;
        _setSwapCaps(buyCap, type(uint256).max);

        deal(address(weth), address(originARM), 10 ether);
        deal(address(oeth), alice, buyCap);
        vm.startPrank(alice);
        oeth.approve(address(originARM), type(uint256).max);
        originARM.swapExactTokensForTokens(oeth, weth, 1 ether, 0, alice);
        vm.stopPrank();

        assertEq(originARM.buyLiquidityRemaining(), 2 ether, "buy cap not consumed");
        assertEq(originARM.sellLiquidityRemaining(), type(uint256).max, "sell cap changed");
    }

    function test_SwapTokensForExactTokens_BuySide_ConsumesComputedInputCap() public {
        uint256 buyCap = 3 ether;
        _setSwapCaps(buyCap, type(uint256).max);

        deal(address(weth), address(originARM), 10 ether);
        deal(address(oeth), alice, buyCap);
        vm.startPrank(alice);
        oeth.approve(address(originARM), type(uint256).max);
        uint256[] memory amounts = originARM.swapTokensForExactTokens(oeth, weth, 1 ether, type(uint256).max, alice);
        vm.stopPrank();

        assertEq(originARM.buyLiquidityRemaining(), buyCap - amounts[0], "buy cap not consumed by amount in");
    }

    function test_SwapExactTokensForTokens_SellSide_ConsumesLiquidityAssetCap() public {
        uint256 sellCap = 4 ether;
        _setSwapCaps(type(uint256).max, sellCap);

        deal(address(oeth), address(originARM), 10 ether);
        deal(address(weth), alice, sellCap);
        vm.startPrank(alice);
        weth.approve(address(originARM), type(uint256).max);
        originARM.swapExactTokensForTokens(weth, oeth, 1 ether, 0, alice);
        vm.stopPrank();

        assertEq(originARM.sellLiquidityRemaining(), 3 ether, "sell cap not consumed");
        assertEq(originARM.buyLiquidityRemaining(), type(uint256).max, "buy cap changed");
    }

    function test_SwapTokensForExactTokens_SellSide_ConsumesComputedInputCap() public {
        uint256 sellCap = 4 ether;
        _setSwapCaps(type(uint256).max, sellCap);

        deal(address(oeth), address(originARM), 10 ether);
        deal(address(weth), alice, sellCap);
        vm.startPrank(alice);
        weth.approve(address(originARM), type(uint256).max);
        uint256[] memory amounts = originARM.swapTokensForExactTokens(weth, oeth, 1 ether, type(uint256).max, alice);
        vm.stopPrank();

        assertEq(originARM.sellLiquidityRemaining(), sellCap - amounts[0], "sell cap not consumed by amount in");
    }

    function test_RevertWhen_BuySideSwapExceedsRemainingCap() public {
        _setSwapCaps(1 ether, type(uint256).max);

        deal(address(weth), address(originARM), 10 ether);
        deal(address(oeth), alice, 2 ether);
        vm.startPrank(alice);
        oeth.approve(address(originARM), type(uint256).max);

        vm.expectRevert("ARM: Insufficient liquidity");
        originARM.swapExactTokensForTokens(oeth, weth, 1 ether + 1, 0, alice);

        vm.stopPrank();
    }

    function test_RevertWhen_SellSideSwapExceedsRemainingCap() public {
        _setSwapCaps(type(uint256).max, 1 ether);

        deal(address(oeth), address(originARM), 10 ether);
        deal(address(weth), alice, 2 ether);
        vm.startPrank(alice);
        weth.approve(address(originARM), type(uint256).max);

        vm.expectRevert("ARM: Insufficient liquidity");
        originARM.swapExactTokensForTokens(weth, oeth, 1 ether + 1, 0, alice);

        vm.stopPrank();
    }

    function _setSwapCaps(uint256 buyCap, uint256 sellCap) internal {
        vm.prank(operator);
        originARM.setPrices(992 * 1e33, 1001 * 1e33, buyCap, sellCap);
    }
}
