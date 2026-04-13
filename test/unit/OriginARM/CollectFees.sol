// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {AbstractARM} from "src/contracts/AbstractARM.sol";

contract Unit_Concrete_OriginARM_CollectFees_Test_ is Unit_Shared_Test {
    function _swapBaseForLiquidity(uint256 amountOut) internal returns (uint256 amountIn, uint256 expectedFee) {
        vm.startPrank(bob);
        deal(address(oeth), bob, 1_000 * DEFAULT_AMOUNT);
        oeth.approve(address(originARM), type(uint256).max);
        uint256[] memory amounts =
            originARM.swapTokensForExactTokens(oeth, weth, amountOut, type(uint256).max, bob);
        vm.stopPrank();

        amountIn = amounts[0];
        expectedFee = (amountIn - amountOut) * originARM.fee() / originARM.FEE_SCALE();
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
        vm.expectRevert("ARM: insufficient liquidity");
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
}
