// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract Unit_Concrete_OriginARM_SwapLiquidityFromMarket_Test_ is Unit_Shared_Test {
    function test_SwapExactTokensForTokens_WithMarketShortfall_WithdrawsExactShortfall()
        public
        deposit(alice, 2 * DEFAULT_AMOUNT)
        addMarket(address(market))
        setActiveMarket(address(market))
    {
        address swapper = makeAddr("swapper");
        uint256 amountIn = DEFAULT_AMOUNT / 2;
        uint256 expectedAmountOut = amountIn * originARM.traderate1() / 1e36;
        vm.prank(operator);
        originARM.setPrices(992 * 1e33, 1001 * 1e33, expectedAmountOut, type(uint256).max);

        deal(address(oeth), swapper, amountIn);
        vm.startPrank(swapper);
        oeth.approve(address(originARM), amountIn);

        uint256 marketBalanceBefore = market.balanceOf(address(originARM));
        uint256[] memory amounts = originARM.swapExactTokensForTokens(oeth, weth, amountIn, expectedAmountOut, swapper);

        vm.stopPrank();

        assertEq(amounts[0], amountIn, "input amount");
        assertEq(amounts[1], expectedAmountOut, "output amount");
        assertEq(weth.balanceOf(address(originARM)), 0, "no extra WETH should stay in ARM");
        assertEq(market.balanceOf(address(originARM)), marketBalanceBefore - expectedAmountOut, "market shortfall only");
        assertEq(originARM.buyLiquidityRemaining(), 0, "buy cap not consumed");
    }

    function test_SwapTokensForExactTokens_WithMarketShortfall_WithdrawsExactShortfall()
        public
        deposit(alice, 2 * DEFAULT_AMOUNT)
        addMarket(address(market))
        setActiveMarket(address(market))
    {
        address swapper = makeAddr("swapper");
        uint256 amountOut = DEFAULT_AMOUNT / 2;
        vm.prank(operator);
        originARM.setPrices(992 * 1e33, 1001 * 1e33, amountOut, type(uint256).max);

        deal(address(oeth), swapper, DEFAULT_AMOUNT);
        vm.startPrank(swapper);
        oeth.approve(address(originARM), type(uint256).max);

        uint256 marketBalanceBefore = market.balanceOf(address(originARM));
        uint256[] memory amounts = originARM.swapTokensForExactTokens(oeth, weth, amountOut, type(uint256).max, swapper);

        vm.stopPrank();

        assertEq(amounts[1], amountOut, "exact output");
        assertEq(weth.balanceOf(address(originARM)), 0, "no extra WETH should stay in ARM");
        assertEq(market.balanceOf(address(originARM)), marketBalanceBefore - amountOut, "market shortfall only");
        assertEq(originARM.buyLiquidityRemaining(), 0, "buy cap not consumed");
    }

    function test_SwapWithdrawFromMarket_PreservesQueuedRedeemLiquidity()
        public
        deposit(alice, 4 * DEFAULT_AMOUNT)
        addMarket(address(market))
        setActiveMarket(address(market))
    {
        uint256 sharesToRedeem = originARM.balanceOf(alice) / 4;
        vm.prank(alice);
        (, uint256 queuedAssets) = originARM.requestRedeem(sharesToRedeem);

        address swapper = makeAddr("swapper");
        uint256 amountOut = DEFAULT_AMOUNT / 2;
        deal(address(oeth), swapper, DEFAULT_AMOUNT);

        vm.startPrank(swapper);
        oeth.approve(address(originARM), type(uint256).max);
        originARM.swapTokensForExactTokens(oeth, weth, amountOut, type(uint256).max, swapper);
        vm.stopPrank();

        assertEq(originARM.withdrawsQueued() - originARM.withdrawsClaimed(), queuedAssets, "queued amount tracked");
        assertEq(weth.balanceOf(address(originARM)), queuedAssets, "queued redeem liquidity remains in ARM");
    }

    function test_RevertWhen_SwapNeedsMarketLiquidity_ButNoActiveMarket() public {
        address swapper = makeAddr("swapper");
        uint256 amountOut = DEFAULT_AMOUNT;

        deal(address(oeth), swapper, DEFAULT_AMOUNT * 2);
        vm.startPrank(swapper);
        oeth.approve(address(originARM), type(uint256).max);

        vm.expectRevert("ARM: Insufficient liquidity");
        originARM.swapTokensForExactTokens(oeth, weth, amountOut, type(uint256).max, swapper);

        vm.stopPrank();
    }

    function test_RevertWhen_SwapNeedsMoreLiquidityThanMarketCanProvide()
        public
        deposit(alice, 2 * DEFAULT_AMOUNT)
        addMarket(address(market))
        setActiveMarket(address(market))
    {
        address swapper = makeAddr("swapper");
        uint256 amountOut = DEFAULT_AMOUNT / 2;

        deal(address(oeth), swapper, DEFAULT_AMOUNT);
        vm.mockCallRevert(
            address(market),
            abi.encodeWithSelector(IERC4626.withdraw.selector, amountOut, address(originARM), address(originARM)),
            bytes("mock market withdraw failure")
        );

        vm.startPrank(swapper);
        oeth.approve(address(originARM), type(uint256).max);

        vm.expectRevert("ARM: Insufficient liquidity");
        originARM.swapTokensForExactTokens(oeth, weth, amountOut, type(uint256).max, swapper);

        vm.stopPrank();
    }

    function test_SwapWithEnoughOnHandLiquidity_DoesNotTouchMarket()
        public
        deposit(alice, DEFAULT_AMOUNT)
        setARMBuffer(1 ether)
        addMarket(address(market))
        setActiveMarket(address(market))
    {
        address swapper = makeAddr("local liquidity swapper");
        uint256 amountOut = DEFAULT_AMOUNT / 2;

        deal(address(oeth), swapper, DEFAULT_AMOUNT);
        vm.startPrank(swapper);
        oeth.approve(address(originARM), type(uint256).max);

        uint256 marketBalanceBefore = market.balanceOf(address(originARM));
        originARM.swapTokensForExactTokens(oeth, weth, amountOut, type(uint256).max, swapper);

        vm.stopPrank();

        assertEq(market.balanceOf(address(originARM)), marketBalanceBefore, "market balance should not change");
    }
}
