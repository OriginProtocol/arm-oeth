// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {AbstractARM} from "src/contracts/AbstractARM.sol";

contract Unit_Concrete_OriginARM_CollectFees_Test_ is Unit_Shared_Test {
    function _swapBaseForLiquidity(uint256 amountOut) internal returns (uint256 amountIn, uint256 expectedFee) {
        vm.startPrank(bob);
        deal(address(oeth), bob, 1_000 * DEFAULT_AMOUNT);
        oeth.approve(address(originARM), type(uint256).max);
        uint256[] memory amounts = originARM.swapTokensForExactTokens(oeth, weth, amountOut, type(uint256).max, bob);
        vm.stopPrank();

        amountIn = amounts[0];
        expectedFee = amountOut * _swapFeeMultiplier(_buyPrice(), _crossPrice(), originARM.fee()) / PRICE_SCALE;
    }

    function test_RevertWhen_CollectFees_Because_InsufficientLiquidity() public deposit(alice, DEFAULT_AMOUNT) {
        _swapBaseForLiquidity(DEFAULT_AMOUNT / 2);
        uint256 shares = originARM.balanceOf(alice);
        vm.prank(alice);
        originARM.requestRedeem(shares);

        vm.prank(vm.randomAddress());
        vm.expectRevert("ARM: Insufficient liquidity");
        originARM.collectFees();
    }

    function test_RevertWhen_CollectFees_Because_InsufficientLiquidityBis() public {
        _swapBaseForLiquidity(1e12);

        vm.prank(vm.randomAddress());
        vm.expectRevert("ARM: Insufficient liquidity");
        originARM.collectFees();
    }

    function test_CollectFees_When_NoFeeToCollect() public deposit(alice, DEFAULT_AMOUNT) requestRedeemAll(alice) {
        uint256 collectorBalance = weth.balanceOf(feeCollector);

        // Collect fees
        vm.prank(vm.randomAddress());
        originARM.collectFees();

        // Ensure there nothing has been allocated
        assertEq(weth.balanceOf(feeCollector), collectorBalance, "Collector balance should not change");
    }

    function test_CollectFees_When_FeeToCollect() public {
        uint256 collectorBalance = weth.balanceOf(feeCollector);
        deal(address(weth), address(originARM), DEFAULT_AMOUNT);
        (, uint256 expectedFees) = _swapBaseForLiquidity(DEFAULT_AMOUNT / 2);

        vm.expectEmit(address(originARM));
        emit AbstractARM.FeeCollected(feeCollector, expectedFees);

        // Collect fees
        vm.prank(vm.randomAddress());
        originARM.collectFees();

        // Ensure there nothing has been allocated
        assertEq(weth.balanceOf(feeCollector), collectorBalance + expectedFees, "Collector balance should change");
    }

    function test_SwapFee_IsBoundedByCrossPriceNavGain() public {
        uint256 crossPrice = 9998 * 1e32;
        uint256 buyPrice = 9997 * 1e32;
        uint256 amountIn = 100 ether;

        vm.startPrank(governor);
        originARM.setFee(FEE_SCALE / 2);
        originARM.setCrossPrice(address(oeth), crossPrice);
        originARM.setPrices(address(oeth), buyPrice, crossPrice, type(uint128).max, type(uint128).max);
        vm.stopPrank();

        deal(address(weth), address(originARM), amountIn);
        deal(address(oeth), bob, amountIn);
        uint256 totalAssetsBefore = originARM.totalAssets();

        vm.startPrank(bob);
        oeth.approve(address(originARM), amountIn);
        uint256[] memory amounts = originARM.swapExactTokensForTokens(oeth, weth, amountIn, 0, bob);
        vm.stopPrank();

        uint256 amountOut = amounts[1];
        uint256 recognizedNavGain = amountOut * (crossPrice - buyPrice) / buyPrice;
        uint256 expectedFee = amountOut * _swapFeeMultiplier(buyPrice, crossPrice, originARM.fee()) / PRICE_SCALE;

        assertEq(originARM.feesAccrued(), expectedFee, "Wrong bounded swap fee");
        assertLe(originARM.feesAccrued(), recognizedNavGain, "Fee exceeds recognized NAV gain");
        assertGe(originARM.totalAssets(), totalAssetsBefore, "Swap fee should not reduce total assets");
    }
}
