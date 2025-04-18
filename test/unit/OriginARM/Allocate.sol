// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract Unit_Concrete_OriginARM_Allocate_Test_ is Unit_Shared_Test {
    using SafeCast for int256;
    using SafeCast for int128;

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

    // In progress
    /*
    function test_Allocate_When_LiquidityDelta_IsNegative_FullWithdraw_NotEnoughLiquidityOnMarket()
        public
        addMarket(address(market))
        setActiveMarket(address(market))
        setARMBuffer(1 ether) // 100% of the assets in the market
        //deposit(alice, DEFAULT_AMOUNT)
        //requestRedeem(alice, 1 ether) // redeem 100% of shares
        simulateMarketLoss(address(market), 0.5 ether) // simulate a 50% loss on the market
        asRandomCaller
    {
        assertEq(market.balanceOf(address(originARM)), MIN_TOTAL_SUPPLY, "Market balance should be MIN_TOTAL_SUPPLY");
        assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY / 2, "Total assets should be MIN_TOTAL_SUPPLY");

        // Cheat and increase the available assets on ARM
        deal(address(oeth), address(originARM), 1e18);

        // Allocate
        originARM.allocate();

        // Not relevant as loss only simulated, not real
        // assertEq(market.balanceOf(address(originARM)), 0, "Market balance should be 0");
        // assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY / 2, "Total assets should be MIN_TOTAL_SUPPLY");
    }
    */

    // Todo: when liquidityDelta is exactly 0
}
