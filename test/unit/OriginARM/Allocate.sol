// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";

contract Unit_Concrete_OriginARM_Allocate_Test_ is Unit_Shared_Test {
    function test_RevertWhen_Allocate_Because_NotOperator() public addMarket(address(market)) setActiveMarket(address(market)) {
        vm.expectRevert("ARM: Only operator can call this function.");
        originARM.allocate(1);
    }

    function test_RevertWhen_Allocate_Because_NoActiveMarket() public asOperator {
        vm.expectRevert("ARM: no active market");
        originARM.allocate(1);
    }

    function test_Allocate_When_DeltaIsZero()
        public
        addMarket(address(market))
        setActiveMarket(address(market))
        asOperator
    {
        vm.expectEmit(address(originARM));
        emit AbstractARM.Allocated(address(market), 0, 0);

        int256 actualDelta = originARM.allocate(0);

        assertEq(actualDelta, 0, "Actual delta should be zero");
        assertEq(market.balanceOf(address(originARM)), 0, "Market balance should stay zero");
    }

    function test_Allocate_When_DeltaIsPositive()
        public
        addMarket(address(market))
        setActiveMarket(address(market))
        asOperator
    {
        deal(address(weth), address(originARM), 2 * DEFAULT_AMOUNT);

        int256 actualDelta = originARM.allocate(int256(2 * DEFAULT_AMOUNT));

        assertEq(actualDelta, int256(2 * DEFAULT_AMOUNT), "Actual delta should match requested deposit");
        assertEq(market.maxWithdraw(address(originARM)), 2 * DEFAULT_AMOUNT, "Market assets should increase");
    }

    function test_Allocate_When_DeltaIsNegative()
        public
        deposit(alice, DEFAULT_AMOUNT)
        addMarket(address(market))
        setActiveMarket(address(market))
    {
        vm.prank(operator);
        originARM.allocate(int256(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY));

        vm.startPrank(operator);
        int256 actualDelta = originARM.allocate(-int256(DEFAULT_AMOUNT));
        vm.stopPrank();

        assertEq(actualDelta, -int256(DEFAULT_AMOUNT), "Actual delta should match requested withdrawal");
        assertEq(weth.balanceOf(address(originARM)), DEFAULT_AMOUNT, "ARM liquidity should increase");
    }

    function test_Allocate_When_DeltaIsNegative_AndMarketHasLimitedLiquidity()
        public
        deposit(alice, DEFAULT_AMOUNT)
        addMarket(address(market))
        setActiveMarket(address(market))
    {
        vm.prank(operator);
        originARM.allocate(int256(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY));

        uint256 partialWithdrawAmount = (DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY) / 2;
        vm.mockCall(
            address(market),
            abi.encodeWithSignature("maxWithdraw(address)", address(originARM)),
            abi.encode(partialWithdrawAmount)
        );
        vm.mockCall(
            address(market),
            abi.encodeWithSignature("maxRedeem(address)", address(originARM)),
            abi.encode(partialWithdrawAmount)
        );

        vm.prank(operator);
        int256 actualDelta = originARM.allocate(-int256(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY));

        assertLt(actualDelta, 0, "Actual delta should be negative");
        assertGt(actualDelta, -int256(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY), "Actual delta should be partially filled");
    }

    function test_Allocate_When_DeltaIsNegative_AndRedeemBelowMinimum()
        public
        deposit(alice, DEFAULT_AMOUNT)
        addMarket(address(market))
        setActiveMarket(address(market))
    {
        vm.prank(operator);
        originARM.allocate(int256(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY));

        vm.mockCall(address(market), abi.encodeWithSignature("maxWithdraw(address)", address(originARM)), abi.encode(uint256(0)));
        vm.mockCall(
            address(market),
            abi.encodeWithSignature("maxRedeem(address)", address(originARM)),
            abi.encode(originARM.minSharesToRedeem())
        );

        vm.startPrank(operator);
        vm.expectEmit(address(originARM));
        emit AbstractARM.Allocated(address(market), -int256(DEFAULT_AMOUNT), 0);
        int256 actualDelta = originARM.allocate(-int256(DEFAULT_AMOUNT));
        vm.stopPrank();

        assertEq(actualDelta, 0, "Actual delta should be zero");
    }
}
