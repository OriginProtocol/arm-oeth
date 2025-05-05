// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Fork_Shared_Test} from "test/fork/OriginARM/shared/Shared.sol";
import {ISilo, Silo} from "test/fork/OriginARM/shared/ISilo.sol";

contract Fork_Concrete_OriginARM_TotalAsset_Test_ is Fork_Shared_Test {
    function setUp() public virtual override {
        super.setUp();
        silo = Silo(payable(address(market)));
    }

    function test_Fork_TotalAsset_When_HighUtilization()
        public
        setFee(0)
        setARMBuffer(0)
        addMarket(address(market))
        setActiveMarket(address(market))
        deposit(alice, DEFAULT_AMOUNT)
        allocate
    {
        uint256 totalAsset = originARM.totalAssets();
        uint256 claimableBefore = originARM.claimable();
        _marketUtilizedAt(1e18);

        ISilo.UtilizationData memory utilizationAfter = silo.utilizationData();

        assertApproxEqRel(
            utilizationAfter.collateralAssets,
            utilizationAfter.debtAssets,
            1e14,
            "Market utilization should be nearly 100%"
        );
        assertEq(market.maxWithdraw(address(originARM)), 0, "Max withdraw should be 0");
        assertEq(originARM.totalAssets(), totalAsset, "Total asset should be the same");
        assertEq(claimableBefore, totalAsset, "Claimable before should be the same as total asset");
        assertEq(originARM.claimable(), 0, "Claimable after should be 0 as 100% allocated and 100% borrowed");
    }
}
