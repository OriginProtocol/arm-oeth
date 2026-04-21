// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Fork_Shared_Test} from "test/fork/OriginARM/shared/Shared.sol";

contract Fork_Concrete_OriginARM_AllocateWithoutAdapter_Test_ is Fork_Shared_Test {
    function test_Fork_SetActiveMarket_DoesNotAutoAllocate() public addMarket(address(market)) asGovernor {
        assertEq(market.balanceOf(address(originARM)), 0, "shares before");

        originARM.setActiveMarket(address(market));

        assertEq(market.balanceOf(address(originARM)), 0, "shares after");
        assertApproxEqAbs(originARM.totalAssets(), MIN_TOTAL_SUPPLY, 1, "totalAssets after");
    }

    function test_Fork_Allocate_When_DeltaIsPositive()
        public
        addMarket(address(market))
        setActiveMarket(address(market))
        deposit(alice, DEFAULT_AMOUNT)
    {
        vm.prank(operator);
        int256 actualDelta = originARM.allocate(int256(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY));

        assertEq(actualDelta, int256(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY), "Actual delta");
        assertApproxEqAbs(market.maxWithdraw(address(originARM)), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "assets after");
    }

    function test_Fork_Allocate_When_DeltaIsNegative()
        public
        addMarket(address(market))
        setActiveMarket(address(market))
        deposit(alice, DEFAULT_AMOUNT)
    {
        vm.prank(operator);
        originARM.allocate(int256(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY));

        vm.prank(operator);
        int256 actualDelta = originARM.allocate(-int256(DEFAULT_AMOUNT));

        assertEq(actualDelta, -int256(DEFAULT_AMOUNT), "Actual delta");
        assertApproxEqAbs(ws.balanceOf(address(originARM)), DEFAULT_AMOUNT, 1, "ARM liquidity after");
    }

    function test_Fork_Allocate_When_DeltaIsNegative_AndMarketIsFullyUtilized()
        public
        setFee(0)
        addMarket(address(market))
        setActiveMarket(address(market))
        deposit(alice, DEFAULT_AMOUNT)
    {
        vm.prank(operator);
        originARM.allocate(int256(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY));

        _marketUtilizedAt(1e18);
        uint256 totalAssetBefore = originARM.totalAssets();

        vm.prank(operator);
        int256 actualDelta = originARM.allocate(-int256(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY));

        assertEq(actualDelta, 0, "Actual delta");
        assertEq(originARM.totalAssets(), totalAssetBefore, "totalAssets after");
    }
}
