// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {AbstractARM} from "src/contracts/AbstractARM.sol";

contract Unit_Concrete_OriginARM_CollectFees_Test_ is Unit_Shared_Test {
    function test_RevertWhen_CollectFees_Because_InsufficientLiquidity()
        public
        deposit(alice, DEFAULT_AMOUNT)
        requestRedeemAll(alice)
        donate(oeth, address(originARM), DEFAULT_AMOUNT)
        asRandomCaller
    {
        vm.expectRevert("ARM: Insufficient liquidity");
        originARM.collectFees();
    }

    function test_RevertWhen_CollectFees_Because_InsufficientLiquidityBis()
        public
        donate(oeth, address(originARM), DEFAULT_AMOUNT)
        asRandomCaller
    {
        vm.expectRevert("ARM: insufficient liquidity");
        originARM.collectFees();
    }

    function test_CollectFees_When_NoFeeToCollect()
        public
        deposit(alice, DEFAULT_AMOUNT)
        requestRedeemAll(alice)
        asRandomCaller
    {
        uint256 collectorBalance = weth.balanceOf(feeCollector);

        // Collect fees
        originARM.collectFees();

        // Ensure there nothing has been allocated
        assertEq(weth.balanceOf(feeCollector), collectorBalance, "Collector balance should not change");
    }

    function test_CollectFees_When_FeeToCollect()
        public
        donate(weth, address(originARM), DEFAULT_AMOUNT)
        asRandomCaller
    {
        uint256 collectorBalance = weth.balanceOf(feeCollector);
        uint256 feePct = originARM.fee();
        uint256 scale = originARM.FEE_SCALE();
        uint256 expectedFees = DEFAULT_AMOUNT * feePct / scale;

        vm.expectEmit(address(originARM));
        emit AbstractARM.FeeCollected(feeCollector, expectedFees);

        // Collect fees
        originARM.collectFees();

        // Ensure there nothing has been allocated
        assertEq(weth.balanceOf(feeCollector), collectorBalance + expectedFees, "Collector balance should change");
    }
}
