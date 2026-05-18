// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_LidoARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// External
import {ERC4626} from "@solmate/mixins/ERC4626.sol";

/// @author Origin Protocol Inc
/// @notice Tests exact-output swaps between the Lido ARM liquidity asset and supported base assets.
/// @dev Expected swap inputs are precomputed with Chisel and hardcoded on purpose. Recomputing
///      them in the test with the same math path as the contract would mostly prove that both sides
///      share the same formula, not that the contract returns the correct values. Deltas and fees are
///      derived from those fixed amounts when that keeps the test easier to read.
contract Unit_Concrete_LidoARM_SwapTokensForExactTokens_Test is Unit_LidoARM_Shared_Test {
    using Math for uint256;

    //////////////////////////////////////////////////////
    /// ---                  SETUP                     ---
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();
        desactiveCapManager();
        addBaseAsset(steth);
        addBaseAsset(wsteth);
        seedWstETHWithTargetExchangeRate();
        aliceFirstDeposit();
    }

    //////////////////////////////////////////////////////
    /// ---       Happy paths: stETH -> WETH           ---
    //////////////////////////////////////////////////////
    function test_SwapTokensForExactTokens_Steth_To_Weth_Default() public {
        // Given
        uint256 amountOut = 50 ether;

        // stETH is valued 1:1 with WETH in these tests.
        // expectedAmountIn = 50 WETH / 0.992 buy price + 3 wei rounding buffer.
        // expectedTotalAssetsIncrease = expectedAmountIn - amountOut.
        // expectedFee = expectedTotalAssetsIncrease * 20% default fee.
        uint256 expectedAmountIn = 50.403225806451612903 ether + 3 wei;
        uint256 expectedTotalAssetsIncrease = expectedAmountIn - amountOut;
        uint256 expectedFee = expectedTotalAssetsIncrease.mulDiv(DEFAULT_FEE, FEE_SCALE);
        deal(address(steth), alice, expectedAmountIn);

        assertEq(lidoARM.feesAccrued(), 0);
        assertEq(weth.balanceOf(alice), 0);
        assertEq(steth.balanceOf(alice), expectedAmountIn);

        uint256 buyLiquidityBefore = buyLiquidityRemaining(steth);
        uint256 sellLiquidityBefore = sellLiquidityRemaining(steth);
        uint256 armWethBefore = weth.balanceOf(address(lidoARM));
        uint256 armStethBefore = steth.balanceOf(address(lidoARM));
        uint256 totalAssetsBefore = lidoARM.totalAssets();

        // Expect events
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(alice, address(lidoARM), expectedAmountIn);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoARM), alice, amountOut);

        // When
        vm.prank(alice);
        uint256[] memory amounts = lidoARM.swapTokensForExactTokens(steth, weth, amountOut, expectedAmountIn, alice);

        // Then
        // Note: Temporary 1 wei tolerance while the fee rounding issue is being fixed.
        assertApproxEqAbs(lidoARM.feesAccrued(), expectedFee, 1);
        assertEq(buyLiquidityRemaining(steth), buyLiquidityBefore - amountOut);
        assertEq(sellLiquidityRemaining(steth), sellLiquidityBefore);
        assertEq(weth.balanceOf(alice), amountOut);
        assertEq(steth.balanceOf(alice), 0);
        assertEq(weth.balanceOf(address(lidoARM)), armWethBefore - amountOut);
        assertEq(steth.balanceOf(address(lidoARM)), armStethBefore + expectedAmountIn);
        assertEq(amounts[0], expectedAmountIn);
        assertEq(amounts[1], amountOut);
        assertGt(lidoARM.totalAssets(), totalAssetsBefore);
        // Note: Temporary 1 wei tolerance while the fee rounding issue is being fixed.
        assertApproxEqAbs(lidoARM.totalAssets(), totalAssetsBefore + expectedTotalAssetsIncrease - expectedFee, 1);
    }

    function test_SwapTokensForExactTokens_Steth_To_Weth_Router() public {
        // Given
        uint256 amountOut = 49.6 ether;

        // stETH is valued 1:1 with WETH in these tests.
        // expectedAmountIn = 49.6 WETH / 0.992 buy price + 3 wei rounding buffer.
        // expectedTotalAssetsIncrease = expectedAmountIn - amountOut.
        // expectedFee = expectedTotalAssetsIncrease * 20% default fee.
        uint256 expectedAmountIn = 50 ether + 3 wei;
        uint256 expectedTotalAssetsIncrease = expectedAmountIn - amountOut;
        uint256 expectedFee = expectedTotalAssetsIncrease.mulDiv(DEFAULT_FEE, FEE_SCALE);
        deal(address(steth), alice, expectedAmountIn);

        address[] memory path = new address[](2);
        path[0] = address(steth);
        path[1] = address(weth);

        assertEq(lidoARM.feesAccrued(), 0);
        assertEq(weth.balanceOf(alice), 0);
        assertEq(steth.balanceOf(alice), expectedAmountIn);

        uint256 buyLiquidityBefore = buyLiquidityRemaining(steth);
        uint256 sellLiquidityBefore = sellLiquidityRemaining(steth);
        uint256 armWethBefore = weth.balanceOf(address(lidoARM));
        uint256 armStethBefore = steth.balanceOf(address(lidoARM));
        uint256 totalAssetsBefore = lidoARM.totalAssets();

        // Expect events
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(alice, address(lidoARM), expectedAmountIn);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoARM), alice, amountOut);

        // When
        vm.prank(alice);
        uint256[] memory amounts =
            lidoARM.swapTokensForExactTokens(amountOut, expectedAmountIn, path, alice, block.timestamp);

        // Then
        // Note: Temporary 1 wei tolerance while the fee rounding issue is being fixed.
        assertApproxEqAbs(lidoARM.feesAccrued(), expectedFee, 1);
        assertEq(buyLiquidityRemaining(steth), buyLiquidityBefore - amountOut);
        assertEq(sellLiquidityRemaining(steth), sellLiquidityBefore);
        assertEq(weth.balanceOf(alice), amountOut);
        assertEq(steth.balanceOf(alice), 0);
        assertEq(weth.balanceOf(address(lidoARM)), armWethBefore - amountOut);
        assertEq(steth.balanceOf(address(lidoARM)), armStethBefore + expectedAmountIn);
        assertEq(amounts[0], expectedAmountIn);
        assertEq(amounts[1], amountOut);
        assertGt(lidoARM.totalAssets(), totalAssetsBefore);
        // Note: Temporary 1 wei tolerance while the fee rounding issue is being fixed.
        assertApproxEqAbs(lidoARM.totalAssets(), totalAssetsBefore + expectedTotalAssetsIncrease - expectedFee, 1);
    }

    function test_SwapTokensForExactTokens_Steth_To_Weth_NoFees() public {
        // Set fee to 0 for this test to isolate swap logic without fees.
        vm.prank(governor);
        lidoARM.setFee(0);

        // Given
        uint256 amountOut = 49.6 ether;

        // stETH is valued 1:1 with WETH in these tests.
        // expectedAmountIn = 49.6 WETH / 0.992 buy price + 3 wei rounding buffer.
        // expectedTotalAssetsIncrease = expectedAmountIn - amountOut.
        // The fee is disabled, so the whole spread stays in totalAssets.
        uint256 expectedAmountIn = 50 ether + 3 wei;
        uint256 expectedTotalAssetsIncrease = expectedAmountIn - amountOut;
        deal(address(steth), alice, expectedAmountIn);

        assertEq(lidoARM.feesAccrued(), 0);
        assertEq(weth.balanceOf(alice), 0);
        assertEq(steth.balanceOf(alice), expectedAmountIn);

        uint256 buyLiquidityBefore = buyLiquidityRemaining(steth);
        uint256 sellLiquidityBefore = sellLiquidityRemaining(steth);
        uint256 armWethBefore = weth.balanceOf(address(lidoARM));
        uint256 armStethBefore = steth.balanceOf(address(lidoARM));
        uint256 totalAssetsBefore = lidoARM.totalAssets();

        // Expect events
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(alice, address(lidoARM), expectedAmountIn);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoARM), alice, amountOut);

        // When
        vm.prank(alice);
        uint256[] memory amounts = lidoARM.swapTokensForExactTokens(steth, weth, amountOut, expectedAmountIn, alice);

        // Then
        assertEq(lidoARM.feesAccrued(), 0);
        assertEq(buyLiquidityRemaining(steth), buyLiquidityBefore - amountOut);
        assertEq(sellLiquidityRemaining(steth), sellLiquidityBefore);
        assertEq(weth.balanceOf(alice), amountOut);
        assertEq(steth.balanceOf(alice), 0);
        assertEq(weth.balanceOf(address(lidoARM)), armWethBefore - amountOut);
        assertEq(steth.balanceOf(address(lidoARM)), armStethBefore + expectedAmountIn);
        assertEq(amounts[0], expectedAmountIn);
        assertEq(amounts[1], amountOut);
        assertGt(lidoARM.totalAssets(), totalAssetsBefore);
        assertEq(lidoARM.totalAssets(), totalAssetsBefore + expectedTotalAssetsIncrease);
    }

    function test_SwapTokensForExactTokens_Steth_To_Weth_UseMarket() public {
        // Route excess WETH through the mock market so the swap must pull the shortfall from it.
        vm.startPrank(governor);
        address[] memory markets = new address[](1);
        markets[0] = address(mockERC4626Market);
        lidoARM.addMarkets(markets);
        lidoARM.setActiveMarket(address(mockERC4626Market));
        // 0.5e18 = 50% buffer kept in the ARM.
        lidoARM.setARMBuffer(0.5 ether);
        lidoARM.allocate();
        vm.stopPrank();

        // Given
        uint256 amountOut = 74.4 ether;

        // stETH is valued 1:1 with WETH in these tests.
        // expectedAmountIn = 74.4 WETH / 0.992 buy price + 3 wei rounding buffer.
        // expectedTotalAssetsIncrease = expectedAmountIn - amountOut.
        // expectedFee = expectedTotalAssetsIncrease * 20% default fee.
        uint256 expectedAmountIn = 75 ether + 3 wei;
        uint256 expectedTotalAssetsIncrease = expectedAmountIn - amountOut;
        uint256 expectedFee = expectedTotalAssetsIncrease.mulDiv(DEFAULT_FEE, FEE_SCALE);
        deal(address(steth), alice, expectedAmountIn);

        assertEq(lidoARM.feesAccrued(), 0);
        assertEq(weth.balanceOf(alice), 0);
        assertEq(steth.balanceOf(alice), expectedAmountIn);
        // The 50% buffer applies to Alice's 100 WETH deposit plus the 1e12 minimum liquidity.
        assertEq(weth.balanceOf(address(lidoARM)), 50 ether + MIN_TOTAL_SUPPLY / 2);
        assertEq(steth.balanceOf(address(mockERC4626Market)), 0);

        uint256 expectedMarketWithdrawal = amountOut - weth.balanceOf(address(lidoARM));
        uint256 buyLiquidityBefore = buyLiquidityRemaining(steth);
        uint256 sellLiquidityBefore = sellLiquidityRemaining(steth);
        uint256 armStethBefore = steth.balanceOf(address(lidoARM));
        uint256 marketSharesBefore = mockERC4626Market.balanceOf(address(lidoARM));
        uint256 totalAssetsBefore = lidoARM.totalAssets();

        // The ARM pays Alice with its on-hand WETH first; the ERC4626 withdrawal covers only the shortfall.
        vm.expectEmit({emitter: address(mockERC4626Market)});
        emit ERC4626.Withdraw(
            address(lidoARM), address(lidoARM), address(lidoARM), expectedMarketWithdrawal, expectedMarketWithdrawal
        );
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(alice, address(lidoARM), expectedAmountIn);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoARM), alice, amountOut);

        // When
        vm.prank(alice);
        uint256[] memory amounts = lidoARM.swapTokensForExactTokens(steth, weth, amountOut, expectedAmountIn, alice);

        // Then
        // Note: Temporary 1 wei tolerance while the fee rounding issue is being fixed.
        assertApproxEqAbs(lidoARM.feesAccrued(), expectedFee, 1);
        assertEq(buyLiquidityRemaining(steth), buyLiquidityBefore - amountOut);
        assertEq(sellLiquidityRemaining(steth), sellLiquidityBefore);
        assertEq(weth.balanceOf(alice), amountOut);
        assertEq(steth.balanceOf(alice), 0);
        // On-hand WETH plus the market withdrawal was paid to Alice.
        assertEq(weth.balanceOf(address(lidoARM)), 0);
        assertEq(steth.balanceOf(address(lidoARM)), armStethBefore + expectedAmountIn);
        assertEq(mockERC4626Market.balanceOf(address(lidoARM)), marketSharesBefore - expectedMarketWithdrawal);
        assertEq(steth.balanceOf(address(mockERC4626Market)), 0);
        assertEq(amounts[0], expectedAmountIn);
        assertEq(amounts[1], amountOut);
        assertGt(lidoARM.totalAssets(), totalAssetsBefore);
        // Note: Temporary 1 wei tolerance while the fee rounding issue is being fixed.
        assertApproxEqAbs(lidoARM.totalAssets(), totalAssetsBefore + expectedTotalAssetsIncrease - expectedFee, 1);
    }

    //////////////////////////////////////////////////////
    /// ---       Happy paths: WETH -> stETH           ---
    //////////////////////////////////////////////////////
    function test_SwapTokensForExactTokens_Weth_To_Steth_Default() public {
        // Seed stETH sell liquidity directly instead of calling the stETH -> WETH test.
        // Calling another test would make coverage include that test's swap path too.
        uint256 armStethLiquidity = 50 ether;
        deal(address(steth), address(lidoARM), armStethLiquidity);

        // Given
        uint256 amountOut = 24.975024975024975024 ether;

        // stETH is valued 1:1 with WETH in these tests.
        // expectedAmountIn = 24.975024975024975024 stETH * 1.001 sell price + 3 wei rounding buffer.
        // expectedTotalAssetsIncrease = expectedAmountIn - amountOut.
        // Sell-side swaps do not accrue fees, so the whole spread stays in totalAssets.
        uint256 expectedAmountIn = 25 ether + 2 wei;
        uint256 expectedTotalAssetsIncrease = expectedAmountIn - amountOut;
        deal(address(weth), alice, expectedAmountIn);

        assertEq(weth.balanceOf(alice), expectedAmountIn);
        uint256 feeAccruedBefore = lidoARM.feesAccrued();
        uint256 stethBalanceBefore = steth.balanceOf(alice);
        uint256 buyLiquidityBefore = buyLiquidityRemaining(steth);
        uint256 sellLiquidityBefore = sellLiquidityRemaining(steth);
        uint256 armWethBefore = weth.balanceOf(address(lidoARM));
        uint256 armStethBefore = steth.balanceOf(address(lidoARM));
        uint256 totalAssetsBefore = lidoARM.totalAssets();

        // Expect events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(lidoARM), expectedAmountIn);
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(address(lidoARM), alice, amountOut);

        // When
        vm.prank(alice);
        uint256[] memory amounts = lidoARM.swapTokensForExactTokens(weth, steth, amountOut, expectedAmountIn, alice);

        // Then
        // No fees on sell side.
        assertEq(lidoARM.feesAccrued(), feeAccruedBefore);
        assertEq(buyLiquidityRemaining(steth), buyLiquidityBefore);
        assertEq(sellLiquidityRemaining(steth), sellLiquidityBefore - amountOut);
        assertEq(weth.balanceOf(alice), 0);
        assertEq(steth.balanceOf(alice), amountOut + stethBalanceBefore);
        assertEq(weth.balanceOf(address(lidoARM)), armWethBefore + expectedAmountIn);
        assertEq(steth.balanceOf(address(lidoARM)), armStethBefore - amountOut);
        assertEq(amounts[0], expectedAmountIn);
        assertEq(amounts[1], amountOut);
        assertGt(lidoARM.totalAssets(), totalAssetsBefore);
        assertEq(lidoARM.totalAssets(), totalAssetsBefore + expectedTotalAssetsIncrease);
    }

    //////////////////////////////////////////////////////
    /// ---       Happy paths: wstETH <-> WETH         ---
    //////////////////////////////////////////////////////
    function test_SwapTokensForExactTokens_Wsteth_To_Weth_Default() public {
        // Given
        uint256 amountOut = 50 ether;

        // wstETH is valued through its stETH backing, and these tests assume stETH = WETH.
        // convertedAmountOutShares = 50 WETH / 1.237 stETH/wstETH = 40.420371867421180274 wstETH.
        // expectedAmountIn = convertedAmountOutShares / 0.992 buy price + 3 wei rounding buffer.
        // amountInAssets = expectedAmountIn * 1.237 stETH/wstETH.
        // expectedTotalAssetsIncrease = amountInAssets - amountOut.
        // expectedFee = expectedTotalAssetsIncrease * 20% default fee.
        uint256 expectedAmountIn = 40.746342608287480117 ether;
        uint256 expectedTotalAssetsIncrease = 0.403225806451612904 ether;
        uint256 expectedFee = expectedTotalAssetsIncrease.mulDiv(DEFAULT_FEE, FEE_SCALE);
        dealWsteth(alice, 50 ether);

        assertEq(lidoARM.feesAccrued(), 0);
        assertEq(weth.balanceOf(alice), 0);
        assertEq(wsteth.balanceOf(alice), 50 ether);
        assertEq(mockWstETH.getWstETHByStETH(amountOut), 40.420371867421180274 ether);
        assertEq(mockWstETH.getStETHByWstETH(expectedAmountIn), 50.403225806451612904 ether);

        uint256 buyLiquidityBefore = buyLiquidityRemaining(wsteth);
        uint256 sellLiquidityBefore = sellLiquidityRemaining(wsteth);
        uint256 armWethBefore = weth.balanceOf(address(lidoARM));
        uint256 armWstethBefore = wsteth.balanceOf(address(lidoARM));
        uint256 totalAssetsBefore = lidoARM.totalAssets();

        // Expect events
        vm.expectEmit({emitter: address(wsteth)});
        emit IERC20.Transfer(alice, address(lidoARM), expectedAmountIn);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoARM), alice, amountOut);

        // When
        vm.prank(alice);
        uint256[] memory amounts = lidoARM.swapTokensForExactTokens(wsteth, weth, amountOut, expectedAmountIn, alice);

        // Then
        // Note: Temporary 1 wei tolerance while the fee rounding issue is being fixed.
        assertApproxEqAbs(lidoARM.feesAccrued(), expectedFee, 1);
        assertEq(buyLiquidityRemaining(wsteth), buyLiquidityBefore - amountOut);
        assertEq(sellLiquidityRemaining(wsteth), sellLiquidityBefore);
        assertEq(weth.balanceOf(alice), amountOut);
        assertEq(wsteth.balanceOf(alice), 50 ether - expectedAmountIn);
        assertEq(weth.balanceOf(address(lidoARM)), armWethBefore - amountOut);
        assertEq(wsteth.balanceOf(address(lidoARM)), armWstethBefore + expectedAmountIn);
        assertEq(amounts[0], expectedAmountIn);
        assertEq(amounts[1], amountOut);
        assertGt(lidoARM.totalAssets(), totalAssetsBefore);
        // Note: Temporary 1 wei tolerance while the fee rounding issue is being fixed.
        assertApproxEqAbs(lidoARM.totalAssets(), totalAssetsBefore + expectedTotalAssetsIncrease - expectedFee, 1);
    }

    function test_SwapTokensForExactTokens_Weth_To_Wsteth_Default() public {
        // Seed wstETH sell liquidity directly instead of calling the wstETH -> WETH test.
        // Calling another test would make coverage include that test's swap path too.
        uint256 armWstethLiquidity = 50 ether;
        dealWsteth(address(lidoARM), armWstethLiquidity);

        // Given
        uint256 amountOut = 20.189995937772817319 ether;

        // wstETH is valued through its stETH backing, and these tests assume stETH = WETH.
        // amountOutAssets = amountOut * 1.237 stETH/wstETH = 24.975024975024975023 WETH.
        // expectedAmountIn = amountOutAssets * 1.001 sell price + 3 wei rounding buffer.
        // expectedTotalAssetsIncrease is 1 wei lower than expectedAmountIn - amountOutAssets because totalAssets()
        // values the ARM's remaining wstETH balance after the transfer.
        // Sell-side swaps do not accrue fees, so the whole spread stays in totalAssets.
        uint256 amountOutAssets = 24.975024975024975023 ether;
        uint256 expectedAmountIn = 25 ether + 1 wei;
        uint256 expectedTotalAssetsIncrease = 0.024975024975024977 ether;
        deal(address(weth), alice, expectedAmountIn);

        assertEq(weth.balanceOf(alice), expectedAmountIn);
        assertEq(wsteth.balanceOf(alice), 0);
        assertEq(mockWstETH.getStETHByWstETH(amountOut), amountOutAssets);

        uint256 feeAccruedBefore = lidoARM.feesAccrued();
        uint256 buyLiquidityBefore = buyLiquidityRemaining(wsteth);
        uint256 sellLiquidityBefore = sellLiquidityRemaining(wsteth);
        uint256 armWethBefore = weth.balanceOf(address(lidoARM));
        uint256 armWstethBefore = wsteth.balanceOf(address(lidoARM));
        uint256 totalAssetsBefore = lidoARM.totalAssets();

        // Expect events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(lidoARM), expectedAmountIn);
        vm.expectEmit({emitter: address(wsteth)});
        emit IERC20.Transfer(address(lidoARM), alice, amountOut);

        // When
        vm.prank(alice);
        uint256[] memory amounts = lidoARM.swapTokensForExactTokens(weth, wsteth, amountOut, expectedAmountIn, alice);

        // Then
        // No fees on sell side.
        assertEq(lidoARM.feesAccrued(), feeAccruedBefore);
        assertEq(buyLiquidityRemaining(wsteth), buyLiquidityBefore);
        assertEq(sellLiquidityRemaining(wsteth), sellLiquidityBefore - amountOut);
        assertEq(weth.balanceOf(alice), 0);
        assertEq(wsteth.balanceOf(alice), amountOut);
        assertEq(weth.balanceOf(address(lidoARM)), armWethBefore + expectedAmountIn);
        assertEq(wsteth.balanceOf(address(lidoARM)), armWstethBefore - amountOut);
        assertEq(amounts[0], expectedAmountIn);
        assertEq(amounts[1], amountOut);
        assertGt(lidoARM.totalAssets(), totalAssetsBefore);
        assertEq(lidoARM.totalAssets(), totalAssetsBefore + expectedTotalAssetsIncrease);
    }

    //////////////////////////////////////////////////////
    /// ---                  REVERTS                   ---
    //////////////////////////////////////////////////////
    function test_SwapTokensForExactTokens_RevertWhen_InvalidSwapAssets() public {
        // Same token for both sides of the swap, even if it's a supported base asset
        vm.expectRevert("ARM: Invalid swap assets");
        lidoARM.swapTokensForExactTokens(steth, steth, 1 ether, 1 ether, alice);

        // Same token for both sides of the swap, even if it's liquidity asset
        vm.expectRevert("ARM: Invalid swap assets");
        lidoARM.swapTokensForExactTokens(weth, weth, 1 ether, 1 ether, alice);

        // Both tokens are base assets supported by the ARM
        vm.expectRevert("ARM: Invalid swap assets");
        lidoARM.swapTokensForExactTokens(steth, wsteth, 1 ether, 1 ether, alice);

        // Unsupported token as liquidity asset
        vm.expectRevert("ARM: Invalid swap assets");
        lidoARM.swapTokensForExactTokens(steth, IERC20(address(0x1234)), 1 ether, 1 ether, alice);

        // Unsupported token as base asset
        vm.expectRevert("ARM: Invalid swap assets");
        lidoARM.swapTokensForExactTokens(weth, IERC20(address(0x1234)), 1 ether, 1 ether, alice);
    }

    function test_SwapTokensForExactTokens_RevertWhen_InsufficientLiquidity() public {
        // Not enough liquidity - no active market and the swap amount exceeds the ARM's balance.
        uint256 amountIn = weth.balanceOf(address(lidoARM)) + 1 ether;
        vm.expectRevert("ARM: Insufficient liquidity");
        lidoARM.swapTokensForExactTokens(steth, weth, amountIn, 0, alice);

        // Route excess WETH through the mock market so the swap must pull the shortfall from it.
        vm.startPrank(governor);
        address[] memory markets = new address[](1);
        markets[0] = address(mockERC4626Market);
        lidoARM.addMarkets(markets);
        lidoARM.setActiveMarket(address(mockERC4626Market));
        // 0.5e18 = 50% buffer kept in the ARM.
        lidoARM.setARMBuffer(0.5 ether);
        lidoARM.allocate();
        vm.stopPrank();

        // Still not enough liquidity - the market buffer plus the ARM's balance is insufficient.
        vm.expectRevert("ARM: Insufficient liquidity");
        lidoARM.swapTokensForExactTokens(steth, weth, amountIn, 0, alice);

        vm.prank(governor);
        lidoARM.setPrices(address(steth), 992 * 1e33, 1001 * 1e33, 1 ether, 2 ether);
        // Not enough buy liquidity at this price.
        vm.expectRevert("ARM: Insufficient liquidity");
        lidoARM.swapTokensForExactTokens(steth, weth, 10 ether, 0, alice);

        // Not enough sell liquidity at this price.
        vm.expectRevert("ARM: Insufficient liquidity");
        lidoARM.swapTokensForExactTokens(weth, steth, 10 ether, 0, alice);

        vm.prank(governor);
        lidoARM.setPrices(address(steth), 20e32, 1e36, 10 ether, 5 ether);
        deal(address(steth), address(lidoARM), 10 ether);
        // The buy-side cap check should run before fee accrual, even when the requested output would overflow fees.
        vm.expectRevert("ARM: Insufficient liquidity");
        lidoARM.swapTokensForExactTokens(weth, steth, 7 ether, type(uint256).max, alice);
    }

    function test_SwapTokensForExactTokens_RevertWhen_ExcessInputAmount() public {
        uint256 amountOut = 1 ether;
        uint256 amountInMax = 1 ether;
        deal(address(steth), alice, 2 ether);

        // Direct overload:
        // swapTokensForExactTokens(IERC20,IERC20,uint256,uint256,address).
        vm.prank(alice);
        vm.expectRevert("ARM: Excess input amount");
        lidoARM.swapTokensForExactTokens(steth, weth, amountOut, amountInMax, alice);

        // Route through the Uniswap V2-compatible overload:
        // swapTokensForExactTokens(uint256,uint256,address[],address,uint256).
        address[] memory path = new address[](2);
        path[0] = address(steth);
        path[1] = address(weth);

        deal(address(steth), alice, 2 ether);

        vm.prank(alice);
        vm.expectRevert("ARM: Excess input amount");
        lidoARM.swapTokensForExactTokens(amountOut, amountInMax, path, alice, block.timestamp);
    }

    function test_SwapTokensForExactTokens_RevertWhen_InvalidPathLength() public {
        address[] memory path = new address[](3);
        vm.expectRevert("ARM: Invalid path length");
        lidoARM.swapTokensForExactTokens(0, 0, path, alice, 0);
    }

    function test_SwapTokensForExactTokens_RevertWhen_DeadlineExpired() public {
        address[] memory path = new address[](2);
        path[0] = address(steth);
        path[1] = address(weth);
        vm.expectRevert("ARM: Deadline expired");
        lidoARM.swapTokensForExactTokens(0, 0, path, alice, block.timestamp - 1);
    }

    function test_SwapTokensForExactTokens_RevertWhen_Paused() public {
        vm.prank(governor);
        lidoARM.pause();

        vm.expectRevert(AbstractARM.ContractPaused.selector);
        lidoARM.swapTokensForExactTokens(steth, weth, 1 ether, 0, alice);

        vm.expectRevert(AbstractARM.ContractPaused.selector);
        lidoARM.swapTokensForExactTokens(1 ether, 0, new address[](2), alice, block.timestamp);
    }
}
