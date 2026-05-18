// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";

contract Unit_Concrete_OriginARM_SwapLiquidityLimits_Test_ is Unit_Shared_Test {
    uint256 internal constant MAX_SWAP_LIQUIDITY = type(uint128).max;

    function test_SwapExactTokensForTokens_BuySide_ConsumesLiquidityAssetCap() public {
        uint256 buyCap = 3 ether;
        _setSwapCaps(buyCap, MAX_SWAP_LIQUIDITY);

        deal(address(weth), address(originARM), 10 ether);
        deal(address(oeth), alice, buyCap);
        vm.startPrank(alice);
        oeth.approve(address(originARM), type(uint256).max);
        uint256[] memory amounts = originARM.swapExactTokensForTokens(oeth, weth, 1 ether, 0, alice);
        vm.stopPrank();

        assertEq(_buyLiquidityRemaining(), buyCap - amounts[1], "buy cap not consumed");
        assertEq(_sellLiquidityRemaining(), MAX_SWAP_LIQUIDITY, "sell cap changed");
    }

    function test_SwapTokensForExactTokens_BuySide_ConsumesExactOutputCap() public {
        uint256 buyCap = 3 ether;
        _setSwapCaps(buyCap, MAX_SWAP_LIQUIDITY);

        deal(address(weth), address(originARM), 10 ether);
        deal(address(oeth), alice, buyCap);
        vm.startPrank(alice);
        oeth.approve(address(originARM), type(uint256).max);
        uint256[] memory amounts = originARM.swapTokensForExactTokens(oeth, weth, 1 ether, type(uint256).max, alice);
        vm.stopPrank();

        assertEq(amounts[1], 1 ether, "wrong output");
        assertEq(_buyLiquidityRemaining(), buyCap - amounts[1], "buy cap not consumed by amount out");
    }

    function test_SwapExactTokensForTokens_BuySide_ConsumesMaxCap() public {
        _setSwapCaps(MAX_SWAP_LIQUIDITY, MAX_SWAP_LIQUIDITY);

        deal(address(weth), address(originARM), 10 ether);
        deal(address(oeth), alice, 3 ether);
        vm.startPrank(alice);
        oeth.approve(address(originARM), type(uint256).max);
        uint256[] memory amounts = originARM.swapExactTokensForTokens(oeth, weth, 1 ether, 0, alice);
        vm.stopPrank();

        assertEq(_buyLiquidityRemaining(), MAX_SWAP_LIQUIDITY - amounts[1], "buy cap not consumed");
        assertEq(_sellLiquidityRemaining(), MAX_SWAP_LIQUIDITY, "sell cap changed");
    }

    function test_SwapExactTokensForTokens_SellSide_ConsumesBaseAssetCap() public {
        uint256 sellCap = 4 ether;
        _setSwapCaps(MAX_SWAP_LIQUIDITY, sellCap);

        deal(address(oeth), address(originARM), 10 ether);
        deal(address(weth), alice, sellCap);
        vm.startPrank(alice);
        weth.approve(address(originARM), type(uint256).max);
        uint256[] memory amounts = originARM.swapExactTokensForTokens(weth, oeth, 1 ether, 0, alice);
        vm.stopPrank();

        assertEq(_sellLiquidityRemaining(), sellCap - amounts[1], "sell cap not consumed");
        assertEq(_buyLiquidityRemaining(), MAX_SWAP_LIQUIDITY, "buy cap changed");
    }

    function test_SwapTokensForExactTokens_SellSide_ConsumesExactOutputCap() public {
        uint256 sellCap = 4 ether;
        _setSwapCaps(MAX_SWAP_LIQUIDITY, sellCap);

        deal(address(oeth), address(originARM), 10 ether);
        deal(address(weth), alice, sellCap);
        vm.startPrank(alice);
        weth.approve(address(originARM), type(uint256).max);
        uint256[] memory amounts = originARM.swapTokensForExactTokens(weth, oeth, 1 ether, type(uint256).max, alice);
        vm.stopPrank();

        assertEq(amounts[1], 1 ether, "wrong output");
        assertEq(_sellLiquidityRemaining(), sellCap - amounts[1], "sell cap not consumed by amount out");
    }

    function test_SwapExactTokensForTokens_SellSide_ConsumesMaxCap() public {
        _setSwapCaps(MAX_SWAP_LIQUIDITY, MAX_SWAP_LIQUIDITY);

        deal(address(oeth), address(originARM), 10 ether);
        deal(address(weth), alice, 3 ether);
        vm.startPrank(alice);
        weth.approve(address(originARM), type(uint256).max);
        uint256[] memory amounts = originARM.swapExactTokensForTokens(weth, oeth, 1 ether, 0, alice);
        vm.stopPrank();

        assertEq(_buyLiquidityRemaining(), MAX_SWAP_LIQUIDITY, "buy cap changed");
        assertEq(_sellLiquidityRemaining(), MAX_SWAP_LIQUIDITY - amounts[1], "sell cap not consumed");
    }

    function test_RevertWhen_BuySideSwapExceedsRemainingCap() public {
        _setSwapCaps(1 ether, MAX_SWAP_LIQUIDITY);

        deal(address(weth), address(originARM), 10 ether);
        deal(address(oeth), alice, 2 ether);
        vm.startPrank(alice);
        oeth.approve(address(originARM), type(uint256).max);

        vm.expectRevert("ARM: Insufficient liquidity");
        originARM.swapTokensForExactTokens(oeth, weth, 1 ether + 1, type(uint256).max, alice);

        vm.stopPrank();
    }

    function test_RevertWhen_SellSideSwapExceedsRemainingCap() public {
        _setSwapCaps(MAX_SWAP_LIQUIDITY, 1 ether);

        deal(address(oeth), address(originARM), 10 ether);
        deal(address(weth), alice, 2 ether);
        vm.startPrank(alice);
        weth.approve(address(originARM), type(uint256).max);

        vm.expectRevert("ARM: Insufficient liquidity");
        originARM.swapTokensForExactTokens(weth, oeth, 1 ether + 1, type(uint256).max, alice);

        vm.stopPrank();
    }

    function test_RevertWhen_SwapExactTokensForTokens_SellSideInsufficientBaseAsset() public {
        _setSwapCaps(MAX_SWAP_LIQUIDITY, MAX_SWAP_LIQUIDITY);

        deal(address(oeth), address(originARM), 0);
        deal(address(weth), alice, 2 ether);
        vm.startPrank(alice);
        weth.approve(address(originARM), type(uint256).max);

        vm.expectRevert("ARM: Insufficient liquidity");
        originARM.swapExactTokensForTokens(weth, oeth, 1 ether, 0, alice);

        vm.stopPrank();
        assertEq(_sellLiquidityRemaining(), MAX_SWAP_LIQUIDITY, "sell cap changed");
    }

    function test_RevertWhen_SwapTokensForExactTokens_SellSideInsufficientBaseAsset() public {
        _setSwapCaps(MAX_SWAP_LIQUIDITY, MAX_SWAP_LIQUIDITY);

        deal(address(oeth), address(originARM), 0);
        deal(address(weth), alice, 2 ether);
        vm.startPrank(alice);
        weth.approve(address(originARM), type(uint256).max);

        vm.expectRevert("ARM: Insufficient liquidity");
        originARM.swapTokensForExactTokens(weth, oeth, 1 ether, type(uint256).max, alice);

        vm.stopPrank();
        assertEq(_sellLiquidityRemaining(), MAX_SWAP_LIQUIDITY, "sell cap changed");
    }

    function _setSwapCaps(uint256 buyCap, uint256 sellCap) internal {
        vm.prank(operator);
        originARM.setPrices(address(oeth), 992 * 1e33, 1001 * 1e33, buyCap, sellCap);
    }
}
