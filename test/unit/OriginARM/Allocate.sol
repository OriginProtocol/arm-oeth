// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";

contract Unit_Concrete_OriginARM_Allocate_Test_ is Unit_Shared_Test {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_RevertWhen_Allocate_Because_NoActiveMarket() public asRandomCaller {
        vm.expectRevert("ARM: no active market");
        originARM.allocate();
    }

    function test_Allocate_When_NoAvailableAsset()
        public
        forceAvailableAssetsToZero
        addMarket(address(market))
        setActiveMarket(address(market))
        asRandomCaller
    {
        // Ensure there is nothing already allocated
        assertEq(market.balanceOf(address(originARM)), 0);

        // Allocated
        originARM.allocate();

        // Ensure there nothing has been allocated
        assertEq(market.balanceOf(address(originARM)), 0);
    }

    function test_Allocate_When_LiquidityDelta_IsPositive_NoOutstandingWithdraw()
        public
        addMarket(address(market))
        setActiveMarket(address(market))
        setARMBuffer(0)
        asRandomCaller
    {
        assertEq(market.balanceOf(address(originARM)), MIN_TOTAL_SUPPLY, "Market balance should be MIN_TOTAL_SUPPLY");

        // Cheat and increase the available assets on ARM
        deal(address(weth), address(originARM), DEFAULT_AMOUNT);

        // Allocate
        originARM.allocate();

        // As we simulate a benefit from trade, we need to check the fees accrued
        uint256 feesAccrued = originARM.feesAccrued();
        assertEq(
            market.balanceOf(address(originARM)),
            MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT,
            "Market balance should be increased by DEFAULT_AMOUNT"
        );
        assertEq(
            originARM.totalAssets(),
            DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY - feesAccrued,
            "Total assets should be DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY"
        );
    }

    function test_Allocate_When_LiquidityDelta_IsPositive_WithOutstandingWithdraw()
        public
        addMarket(address(market))
        setActiveMarket(address(market))
        setARMBuffer(0)
        deposit(alice, 2 * DEFAULT_AMOUNT)
        requestRedeem(alice, 0.5 ether) // redeem 50% of shares
        asRandomCaller
    {
        assertEq(market.balanceOf(address(originARM)), MIN_TOTAL_SUPPLY, "Market balance should be MIN_TOTAL_SUPPLY");
        assertEq(
            originARM.totalAssets(),
            DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY,
            "Total assets should be DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY"
        );

        // Allocate
        originARM.allocate();

        assertEq(
            market.balanceOf(address(originARM)),
            MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT,
            "Market balance should be increased by DEFAULT_AMOUNT"
        );
        assertEq(
            originARM.totalAssets(),
            DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY,
            "Total assets should be DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY"
        );
    }

    /// @dev in this situation there is no direct WETH liquidity and armBuffer is set to 100%
    /// This means that the ARM wants to have 50% of his liquidity out of market.
    function test_Allocate_When_LiquidityDelta_IsNegative_PartialWithdraw_EnoughLiquidityOnMarket()
        public
        addMarket(address(market))
        setActiveMarket(address(market))
        setARMBuffer(0.5 ether) // 50% of the assets in the market
        deposit(alice, DEFAULT_AMOUNT)
        requestRedeem(alice, 1 ether) // redeem 100% of shares
        asRandomCaller
    {
        assertEq(market.balanceOf(address(originARM)), MIN_TOTAL_SUPPLY, "Market balance should be MIN_TOTAL_SUPPLY");
        assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "Total assets should be MIN_TOTAL_SUPPLY");

        // Allocate
        originARM.allocate();

        assertEq(
            market.balanceOf(address(originARM)),
            MIN_TOTAL_SUPPLY / 2,
            "Market balance should be decreased by half of the MIN_TOTAL_SUPPLY"
        );
        assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "Total assets should be MIN_TOTAL_SUPPLY");
        assertEq(
            weth.balanceOf(address(originARM)),
            DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY / 2,
            "WETH balance should be increased"
        );
    }

    function test_Allocate_When_LiquidityDelta_IsNegative_FullWithdraw_EnoughLiquidityOnMarket()
        public
        addMarket(address(market))
        setActiveMarket(address(market))
        setARMBuffer(1 ether) // 100% of the assets in the market
        deposit(alice, DEFAULT_AMOUNT)
        requestRedeem(alice, 1 ether) // redeem 100% of shares
        asRandomCaller
    {
        assertEq(market.balanceOf(address(originARM)), MIN_TOTAL_SUPPLY, "Market balance should be MIN_TOTAL_SUPPLY");
        assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "Total assets should be MIN_TOTAL_SUPPLY");

        // Allocate
        originARM.allocate();

        assertEq(market.balanceOf(address(originARM)), 0, "Market balance should be 0");
        assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "Total assets should be MIN_TOTAL_SUPPLY");
        assertEq(
            weth.balanceOf(address(originARM)), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, "WETH balance should be increased"
        );
    }

    function test_Allocate_When_LiquidityDelta_IsNegative_FullWithdraw_NotEnoughLiquidityOnMarket_BelowThreshold()
        public
        setARMBuffer(0 ether) // 0% of the assets in the market
        addMarket(address(market))
        setActiveMarket(address(market))
        marketLoss(address(market), 0.5 ether) // simulate a 50% loss on the market
        setARMBuffer(1 ether) // 100% of the assets in the market
        asRandomCaller
    {
        assertEq(market.balanceOf(address(originARM)), MIN_TOTAL_SUPPLY, "Market balance should be MIN_TOTAL_SUPPLY");
        assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY / 2, "Total assets should be MIN_TOTAL_SUPPLY/2");

        // Cheat and increase the available assets on ARM
        deal(address(oeth), address(originARM), 1e18);
        // Get fees accrued
        uint256 feesAccrued = originARM.feesAccrued();

        // Allocate
        originARM.allocate();

        assertEq(market.balanceOf(address(originARM)), MIN_TOTAL_SUPPLY, "Market balance should be 0");
        assertEq(
            originARM.totalAssets(),
            DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY / 2 - feesAccrued,
            "Total assets should be correctly updated"
        );
    }

    function test_Allocate_When_LiquidityDelta_IsNegative_FullWithdraw_NotEnoughLiquidityOnMarket_AboveThreshold()
        public
        setFee(0)
        setARMBuffer(0 ether) // 0% of the assets in the market
        deposit(alice, DEFAULT_AMOUNT)
        addMarket(address(market))
        setActiveMarket(address(market)) // this allocate too
        marketLoss(address(market), 0.5 ether) // simulate a 50% loss on the market
        setARMBuffer(1 ether) // 100% of the assets in the market
        asRandomCaller
    {
        assertEq(
            market.balanceOf(address(originARM)),
            DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY,
            "Market balance should be DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY"
        );
        assertEq(
            originARM.totalAssets(),
            (DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY) / 2,
            "Total assets should be (DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY) / 2"
        );

        // Cheat and increase the available assets on ARM
        deal(address(oeth), address(originARM), DEFAULT_AMOUNT);

        // Allocate
        originARM.allocate();

        assertEq(market.balanceOf(address(originARM)), 0, "Market balance should be 0");
        assertEq(
            originARM.totalAssets(),
            DEFAULT_AMOUNT + (DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY) / 2,
            "Total assets should be correctly updated"
        );
    }

    function test_Allocate_When_LiquidityDelta_IsNull()
        public
        setARMBuffer(0.2 ether)
        addMarket(address(market))
        setActiveMarket(address(market))
        asRandomCaller
    {
        assertEq(
            market.balanceOf(address(originARM)),
            MIN_TOTAL_SUPPLY * 80 / 100,
            "Market balance should be MIN_TOTAL_SUPPLY"
        );
        assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "Total assets should be MIN_TOTAL_SUPPLY");

        // Allocate
        originARM.allocate();

        assertEq(market.balanceOf(address(originARM)), MIN_TOTAL_SUPPLY * 80 / 100, "Market balance should be the same");
        assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "Total assets should be the same");
    }
}
