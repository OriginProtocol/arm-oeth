// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_MultiAssetARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

/// @notice Coverage for `AbstractARM.allocate()` / `_allocate()`. Exercises both the deposit
///         (positive delta) and withdraw (negative delta) branches, including the
///         maxRedeem-fallback path when the market cannot meet the desired withdraw amount.
contract Unit_MultiAssetARM_Allocate_Test is Unit_MultiAssetARM_Shared_Test {
    function setUp() public override {
        super.setUp();
        desactiveCapManager();
    }

    function test_Allocate_RevertWhen_NoActiveMarket() public {
        vm.prank(alice);
        vm.expectRevert(AbstractARM.NoActiveMarket.selector);
        arm.allocate();
    }

    function test_Allocate_NoOp_WhenAvailableAssetsZero() public {
        // Drain the ARM so `_availableAssets()` returns zero before activating a market.
        deal(address(liquidity), address(arm), 0);
        addMarket(address(market));
        setActiveMarket(address(market));

        assertEq(market.balanceOf(address(arm)), 0, "market shares pre");

        vm.prank(alice);
        arm.allocate();

        assertEq(market.balanceOf(address(arm)), 0, "market shares post");
    }

    function test_Allocate_PositiveDelta_NoOutstandingWithdraw() public {
        // Stage everything in the ARM under a 100% buffer, then drop the buffer and allocate.
        aliceFirstDeposit();
        addMarket(address(market));
        setARMBuffer(1e18);
        setActiveMarket(address(market));
        assertEq(market.balanceOf(address(arm)), 0, "market pre");

        setARMBuffer(0);
        vm.prank(alice);
        arm.allocate();

        // Everything (100 ether + the init 1e12 dead-share WETH) lands in the market.
        assertEq(market.balanceOf(address(arm)), 100 ether + 1e12, "market post");
        assertEq(liquidity.balanceOf(address(arm)), 0, "ARM WETH post");
        assertEq(arm.totalAssets(), 100 ether + 1e12, "totalAssets preserved");
    }

    function test_Allocate_PositiveDelta_WithOutstandingWithdraw() public {
        // Deposit + outstanding redeem request. The reserved liquidity must stay in the ARM.
        aliceFirstDeposit();
        aliceRequest(50 ether);
        addMarket(address(market));
        setActiveMarket(address(market));

        vm.prank(alice);
        arm.allocate();

        assertEq(market.balanceOf(address(arm)), 50 ether + 1e12, "market post");
        assertEq(liquidity.balanceOf(address(arm)), 50 ether, "reserved liquidity stays in ARM");
        assertEq(arm.reservedWithdrawLiquidity(), 50 ether, "reservedWithdrawLiquidity");
    }

    function test_Allocate_NegativeDelta_PartialWithdraw_EnoughLiquidityOnMarket() public {
        // Push everything into the market, then raise the buffer to 30% and allocate.
        aliceFirstDeposit();
        addMarket(address(market));
        setActiveMarket(address(market));
        // buffer is 0 by default, so the setActiveMarket call already moved everything into the market.
        assertEq(market.balanceOf(address(arm)), 100 ether + 1e12, "market pre");
        assertEq(liquidity.balanceOf(address(arm)), 0, "ARM WETH pre");

        setARMBuffer(0.3 ether);
        vm.prank(alice);
        arm.allocate();

        uint256 expectedArm = (100 ether + 1e12) * 30 / 100;
        uint256 expectedMarket = (100 ether + 1e12) - expectedArm;
        assertEq(liquidity.balanceOf(address(arm)), expectedArm, "ARM WETH post");
        assertEq(market.balanceOf(address(arm)), expectedMarket, "market post");
    }

    function test_Allocate_NegativeDelta_FullWithdraw_EnoughLiquidityOnMarket() public {
        aliceFirstDeposit();
        addMarket(address(market));
        setActiveMarket(address(market));
        assertEq(market.balanceOf(address(arm)), 100 ether + 1e12, "market pre");

        setARMBuffer(1e18); // 100% in ARM
        vm.prank(alice);
        arm.allocate();

        assertEq(market.balanceOf(address(arm)), 0, "market post");
        assertEq(liquidity.balanceOf(address(arm)), 100 ether + 1e12, "ARM WETH post");
    }

    function test_Allocate_NegativeDelta_FullWithdraw_NotEnoughLiquidityOnMarket_AboveThreshold() public {
        // Setup: everything goes into the market, then we simulate a 50% market loss and inflate
        // `_availableAssets` with stETH so `desiredWithdrawAmount > maxWithdraw`, forcing the
        // maxRedeem fallback in `_allocate`.
        aliceFirstDeposit();
        addMarket(address(market));
        setActiveMarket(address(market));
        assertEq(market.balanceOf(address(arm)), 100 ether + 1e12, "market pre");

        // Market loses 50% of its WETH. Shares stay; their convertToAssets value halves.
        uint256 halved = (100 ether + 1e12) / 2;
        deal(address(liquidity), address(market), halved);

        // Phantom stETH in the ARM raises totalAssets above what the market can pay out.
        deal(address(peg18), address(arm), 100 ether);

        setARMBuffer(1e18); // target = full availableAssets
        vm.prank(alice);
        arm.allocate();

        // The fallback redeems all market shares for whatever the market can give (the halved WETH).
        assertEq(market.balanceOf(address(arm)), 0, "market shares post");
        assertEq(liquidity.balanceOf(address(arm)), halved, "ARM WETH post");
        assertEq(peg18.balanceOf(address(arm)), 100 ether, "ARM stETH unchanged");
    }

    function test_Allocate_NegativeDelta_FullWithdraw_NotEnoughLiquidityOnMarket_BelowThreshold() public {
        // Hits the `shares <= minSharesToRedeem` early-return in _allocate (AbstractARM line 1124).
        // We seed the ARM with exactly `minSharesToRedeem` market shares (so the maxRedeem
        // branch is reached but skipped) and inflate _availableAssets with phantom stETH so
        // the withdraw path is triggered in the first place.
        addMarket(address(market));

        // Mint exactly MIN_SHARES_TO_REDEEM market shares to the ARM by having a dummy
        // depositor seed the market on the ARM's behalf. The market is empty, so deposit is 1:1.
        address seeder = makeAddr("marketSeeder");
        deal(address(liquidity), seeder, MIN_SHARES_TO_REDEEM);
        vm.startPrank(seeder);
        liquidity.approve(address(market), MIN_SHARES_TO_REDEEM);
        market.deposit(MIN_SHARES_TO_REDEEM, address(arm));
        vm.stopPrank();
        assertEq(market.balanceOf(address(arm)), MIN_SHARES_TO_REDEEM, "seeded shares");

        setActiveMarket(address(market));

        // Phantom stETH pushes the target far above what the market can pay out.
        deal(address(peg18), address(arm), 100 ether);
        setARMBuffer(1e18);

        uint256 armWethBefore = liquidity.balanceOf(address(arm));

        vm.prank(alice);
        arm.allocate();

        // Early return: nothing moves, the ARM's WETH and market shares stay put.
        assertEq(market.balanceOf(address(arm)), MIN_SHARES_TO_REDEEM, "market shares unchanged");
        assertEq(liquidity.balanceOf(address(arm)), armWethBefore, "ARM WETH unchanged");
        assertEq(peg18.balanceOf(address(arm)), 100 ether, "ARM stETH unchanged");
    }

    function test_Allocate_NullDelta() public {
        // Pre-set a 20% buffer so the initial allocation matches the steady state and the
        // subsequent allocate() call has nothing to move.
        aliceFirstDeposit();
        setARMBuffer(0.2 ether);
        addMarket(address(market));
        setActiveMarket(address(market));

        uint256 expectedArm = (100 ether + 1e12) * 20 / 100;
        uint256 expectedMarket = (100 ether + 1e12) - expectedArm;
        assertEq(liquidity.balanceOf(address(arm)), expectedArm, "ARM WETH pre");
        assertEq(market.balanceOf(address(arm)), expectedMarket, "market pre");

        vm.prank(alice);
        arm.allocate();

        assertEq(liquidity.balanceOf(address(arm)), expectedArm, "ARM WETH post");
        assertEq(market.balanceOf(address(arm)), expectedMarket, "market post");
    }
}
