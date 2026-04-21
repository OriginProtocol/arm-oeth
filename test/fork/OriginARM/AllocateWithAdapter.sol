// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Sonic} from "contracts/utils/Addresses.sol";
import {Fork_Shared_Test} from "test/fork/OriginARM/shared/Shared.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract Fork_Concrete_OriginARM_AllocateWithAdapter_Test_ is Fork_Shared_Test {
    function setUp() public virtual override {
        super.setUp();
        market = IERC4626(address(Sonic.SILO_VARLAMORE_S_VAULT));
    }

    function test_Fork_SetActiveMarket_WithAdapter_DoesNotAutoAllocate() public addMarket(address(siloMarket)) asGovernor {
        assertEq(market.balanceOf(address(siloMarket)), 0, "shares before");

        originARM.setActiveMarket(address(siloMarket));

        assertEq(market.balanceOf(address(siloMarket)), 0, "shares after");
        assertApproxEqAbs(originARM.totalAssets(), MIN_TOTAL_SUPPLY, 1, "totalAssets after");
    }

    function test_Fork_Allocate_WithAdapter_When_DeltaIsPositive()
        public
        addMarket(address(siloMarket))
        setActiveMarket(address(siloMarket))
        deposit(alice, DEFAULT_AMOUNT)
    {
        vm.prank(operator);
        int256 actualDelta = originARM.allocate(int256(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY));

        assertEq(actualDelta, int256(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY), "Actual delta");
        assertApproxEqAbs(siloMarket.maxWithdraw(address(originARM)), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 3, "assets after");
    }

    function test_Fork_Allocate_WithAdapter_When_DeltaIsNegative()
        public
        addMarket(address(siloMarket))
        setActiveMarket(address(siloMarket))
        deposit(alice, DEFAULT_AMOUNT)
    {
        vm.prank(operator);
        originARM.allocate(int256(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY));

        vm.prank(operator);
        int256 actualDelta = originARM.allocate(-int256(DEFAULT_AMOUNT));

        assertLt(actualDelta, 0, "Actual delta should be negative");
        assertApproxEqAbs(ws.balanceOf(address(originARM)), DEFAULT_AMOUNT, 3, "ARM liquidity after");
    }
}
