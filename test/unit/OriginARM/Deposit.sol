// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract Unit_Concrete_OriginARM_Deposit_Test_ is Unit_Shared_Test {
    using SafeCast for int256;
    using SafeCast for int128;

    function setUp() public virtual override {
        super.setUp();

        // Give Alice some WETH
        deal(address(weth), alice, 1_000 * DEFAULT_AMOUNT);

        // Alice approve max WETH to the ARM
        vm.prank(alice);
        weth.approve(address(originARM), type(uint256).max);
    }

    /// @notice Test under the following assumptions:
    /// - WETH in the ARM is MIN_TOTAL_SUPPLY
    /// - OETH in the ARM is null
    /// - vaultWithdrawalAmount is null
    /// - no default market
    /// - no outstanding withdrawal requests
    /// - available assets is not null
    /// - assetIncrease is null
    /// - totalAssets is MIN_TOTAL_SUPPLY
    /// - lastAvailableAssets is MIN_TOTAL_SUPPLY
    function test_Deposit_FirstDeposit() public {
        // Expected values
        uint256 expectedShares = originARM.convertToShares(DEFAULT_AMOUNT);

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.Deposit(alice, DEFAULT_AMOUNT, expectedShares);

        // Alice deposits 1 WETH
        vm.prank(alice);
        originARM.deposit(DEFAULT_AMOUNT);

        // Assertions
        assertEq(
            originARM.lastAvailableAssets().toUint256(),
            DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY,
            "Last available assets should be updated"
        );
    }

    /// @notice Test under the following assumptions:
    /// - WETH in the ARM is null
    /// - OETH in the ARM is approx. MIN_TOTAL_SUPPLY
    /// - vaultWithdrawalAmount is null
    /// - no default market
    /// - no outstanding withdrawal requests
    /// - available assets is not null
    /// - assetIncrease is not null
    /// - totalAssets is approx MIN_TOTAL_SUPPLY
    /// - lastAvailableAssets is MIN_TOTAL_SUPPLY
    /// - fees are not null
    function test_Deposit_When_NoWETH() public {
        // A swap happen before
        vm.startPrank(bob);
        deal(address(oeth), bob, 1_000 * DEFAULT_AMOUNT);
        oeth.approve(address(originARM), type(uint256).max);
        originARM.swapTokensForExactTokens(oeth, weth, 1e12, type(uint256).max, bob);
        vm.stopPrank();
        uint256 accruedFees = originARM.feesAccrued();
        assertEq(weth.balanceOf(address(originARM)), 0, "WETH balance should be 0");
        assertGt(originARM.fee(), 0, "Fee should be greater than 0");
        assertGt(accruedFees, 0, "Fees should be accrued");
        assertGt(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "Total assets should be > MIN_TOTAL_SUPPLY");

        // Expected values
        uint256 expectedShares = originARM.convertToShares(DEFAULT_AMOUNT);
        assertLt(expectedShares, DEFAULT_AMOUNT, "Shares should be less than amount");
        assertGt(expectedShares, DEFAULT_AMOUNT * 99 / 100, "Shares should be close to amount");

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.Deposit(alice, DEFAULT_AMOUNT, expectedShares);

        // Alice deposits 1 WETH
        vm.prank(alice);
        originARM.deposit(DEFAULT_AMOUNT);
        assertEq(accruedFees, originARM.feesAccrued(), "Fees should be accrued");
    }

    /// @notice Test under the following assumptions:
    /// - WETH in the ARM is MIN_TOTAL_SUPPLY / 2
    /// - OETH in the ARM is approx. MIN_TOTAL_SUPPLY / 2
    /// - vaultWithdrawalAmount is null
    /// - no default market
    /// - no outstanding withdrawal requests
    /// - available assets is not null
    /// - assetIncrease is not null
    /// - totalAssets is approx MIN_TOTAL_SUPPLY
    /// - lastAvailableAssets is MIN_TOTAL_SUPPLY
    /// - fees are not null
    function test_Deposit_When_HalfWETHOETH() public {
        // A swap happen before
        vm.startPrank(bob);
        deal(address(oeth), bob, 1_000 * DEFAULT_AMOUNT);
        oeth.approve(address(originARM), type(uint256).max);
        originARM.swapTokensForExactTokens(oeth, weth, 1e12 / 2, type(uint256).max, bob);
        vm.stopPrank();
        uint256 accruedFees = originARM.feesAccrued();
        assertEq(weth.balanceOf(address(originARM)), 1e12 / 2, "WETH balance should be 1e12/2");
        assertGt(originARM.fee(), 0, "Fee should be greater than 0");
        assertGt(accruedFees, 0, "Fees should be accrued");
        assertGt(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "Total assets should be > MIN_TOTAL_SUPPLY");

        // Expected values
        uint256 expectedShares = originARM.convertToShares(DEFAULT_AMOUNT);
        assertLt(expectedShares, DEFAULT_AMOUNT, "Shares should be less than amount");
        assertGt(expectedShares, DEFAULT_AMOUNT * 99 / 100, "Shares should be close to amount");

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.Deposit(alice, DEFAULT_AMOUNT, expectedShares);

        // Alice deposits 1 WETH
        vm.prank(alice);
        originARM.deposit(DEFAULT_AMOUNT);
        assertEq(accruedFees, originARM.feesAccrued(), "Fees should be accrued");
    }

    /// @notice Test under the following assumptions:
    /// - WETH in the ARM is MIN_TOTAL_SUPPLY / 2
    /// - OETH in the ARM is approx. null
    /// - vaultWithdrawalAmount is not null
    /// - no default market
    /// - no outstanding withdrawal requests
    /// - available assets is not null
    /// - assetIncrease is not null
    /// - totalAssets is approx MIN_TOTAL_SUPPLY
    /// - lastAvailableAssets is MIN_TOTAL_SUPPLY / 2
    /// - fees are not null
    function test_Deposit_When_VaultWithdrawalAmount_IsNotNull() public {
        // First there is a swap to convert WETH in OETH
        vm.startPrank(bob);
        deal(address(oeth), bob, 1_000 * DEFAULT_AMOUNT);
        oeth.approve(address(originARM), type(uint256).max);
        originARM.swapTokensForExactTokens(oeth, weth, 1e12 / 2, type(uint256).max, bob);
        vm.stopPrank();

        // Then request a withdrawal, this will decrease the available assets
        vm.prank(governor);
        originARM.requestOriginWithdrawal(1e12 / 2);
        uint256 lastAvailableAssets = originARM.lastAvailableAssets().toUint256();

        // Expected values
        uint256 expectedShares = originARM.convertToShares(DEFAULT_AMOUNT);
        assertApproxEqAbs(expectedShares, DEFAULT_AMOUNT, 1e16, "Shares should be eq amount");
        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.Deposit(alice, DEFAULT_AMOUNT, expectedShares);
        // Alice deposits 1 WETH
        vm.prank(alice);
        originARM.deposit(DEFAULT_AMOUNT);
        // Assertions
        assertEq(
            originARM.lastAvailableAssets().toUint256(),
            DEFAULT_AMOUNT + lastAvailableAssets,
            "Last available assets should be updated"
        );
    }

    /// @notice Test under the following assumptions:
    /// - WETH in the ARM is null (all in market)
    /// - OETH in the ARM is null
    /// - vaultWithdrawalAmount is null
    /// - default market is set
    /// - no outstanding withdrawal requests
    /// - available assets is not null
    /// - assetIncrease is null
    /// - totalAssets is approx MIN_TOTAL_SUPPLY
    /// - lastAvailableAssets is approx MIN_TOTAL_SUPPLY
    /// - fees are not null
    function test_Deposit_When_DefaultStrategyIsSet()
        public
        setARMBuffer(1e18)
        addMarket(address(market))
        setActiveMarket(address(market))
    {
        // Allocated as been call in the modifier

        // Expected values
        uint256 expectedShares = originARM.convertToShares(DEFAULT_AMOUNT);
        assertEq(expectedShares, DEFAULT_AMOUNT, "Shares should be eq amount");
        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.Deposit(alice, DEFAULT_AMOUNT, expectedShares);
        // Alice deposits 1 WETH
        vm.prank(alice);
        originARM.deposit(DEFAULT_AMOUNT);
        // Assertions
        assertEq(
            originARM.lastAvailableAssets().toUint256(),
            DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY,
            "Last available assets should be updated"
        );
    }
}
