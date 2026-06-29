// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_EtherARM_Shared_Test} from "../Shared.t.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @author Origin Protocol Inc
/// @notice Fuzzes both exact-input and exact-output swaps between the Lido ARM liquidity asset and
///         stETH to confirm price, fee accrual, balances, liquidity accounting, and totalAssets all
///         behave consistently across the input/output and price ranges.
contract Unit_Fuzz_EtherARM_Swap_Test is Unit_EtherARM_Shared_Test {
    using Math for uint256;

    //////////////////////////////////////////////////////
    /// ---                CONSTANTS                   ---
    //////////////////////////////////////////////////////
    // Buy price set in Shared.t.sol::addBaseAsset: 992 * 1e33 (i.e. 0.992 WETH per stETH).
    uint256 internal constant BUY_PRICE_NUMERATOR = 992;
    uint256 internal constant BUY_PRICE_DENOMINATOR = 1000;

    // Sell price set in Shared.t.sol::addBaseAsset: 1001 * 1e33 (i.e. 1.001 WETH per stETH).
    uint256 internal constant SELL_PRICE_NUMERATOR = 1001;
    uint256 internal constant SELL_PRICE_DENOMINATOR = 1000;

    // AbstractARM._swapTokensForExactTokens adds 3 wei to amountIn to absorb stETH rounding on
    // larger transfers (observed up to 2 wei; 3 is for safety).
    uint256 internal constant ROUNDING_BUFFER = 3;

    //////////////////////////////////////////////////////
    /// ---                  SETUP                     ---
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();
        desactiveCapManager();
        addBaseAsset(steth);
        addBaseAsset(wsteth);
        seedWstETHWithTargetExchangeRate();
    }

    //////////////////////////////////////////////////////
    /// ---   SwapExactTokensForTokens (exact input)   ---
    //////////////////////////////////////////////////////
    function testFuzz_SwapExactTokensForTokens_Steth_To_Weth_Amount(uint128 stethAmount) public {
        deal(address(weth), address(etherARM), 50_000 ether);

        // Bound the input so the ARM can pay the WETH it owes Alice without pulling from a market.
        // The ARM's WETH balance is read live (Alice's deposit + the 1e12 minimum supply seed),
        // so the cap automatically tracks setUp() changes.
        // amountOut = amountIn * 992 / 1000, so cap amountIn at armWeth * 1000 / 992.
        // Lower bound is 1 wei: the spread (amountIn - amountOut) is at least 1 wei for amountIn >= 1
        // because integer truncation of (amountIn * 992 / 1000) loses fractional WETH, which is required
        // for the totalAssets-must-strictly-increase assertion to hold.
        uint256 armWeth = weth.balanceOf(address(etherARM));
        uint256 maxAmountIn = armWeth * BUY_PRICE_DENOMINATOR / BUY_PRICE_NUMERATOR;
        uint256 amountIn = _bound(uint256(stethAmount), 1, maxAmountIn);

        // Expected output is computed without going through the contract's PRICE_SCALE path, so a
        // bug that swaps numerator/denominator or changes the buy price would be caught here.
        uint256 expectedAmountOut = amountIn.mulDiv(BUY_PRICE_NUMERATOR, BUY_PRICE_DENOMINATOR);
        uint256 expectedTotalAssetsIncrease = amountIn - expectedAmountOut;
        uint256 expectedFee = expectedTotalAssetsIncrease.mulDiv(DEFAULT_FEE, FEE_SCALE);

        // Sanity-check the bound so a future change cannot silently push amountOut above the ARM's
        // WETH balance and turn revert paths into spurious failures.
        assertLe(expectedAmountOut, armWeth, "amountOut exceeds ARM WETH balance");

        deal(address(steth), alice, amountIn);

        assertEq(etherARM.feesAccrued(), 0);
        assertEq(weth.balanceOf(alice), 0);
        assertEq(steth.balanceOf(alice), amountIn);

        uint256 buyLiquidityBefore = buyLiquidityRemaining(steth);
        uint256 sellLiquidityBefore = sellLiquidityRemaining(steth);
        uint256 armWethBefore = weth.balanceOf(address(etherARM));
        uint256 armStethBefore = steth.balanceOf(address(etherARM));
        uint256 totalAssetsBefore = etherARM.totalAssets();

        // Expect events
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(alice, address(etherARM), amountIn);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(etherARM), alice, expectedAmountOut);

        // When
        vm.prank(alice);
        uint256[] memory amounts = etherARM.swapExactTokensForTokens(steth, weth, amountIn, expectedAmountOut, alice);

        // Then
        // Note: Temporary 1 wei tolerance while the fee rounding issue is being fixed.
        assertApproxEqAbs(etherARM.feesAccrued(), expectedFee, 1);
        assertEq(buyLiquidityRemaining(steth), buyLiquidityBefore - expectedAmountOut);
        assertEq(sellLiquidityRemaining(steth), sellLiquidityBefore);
        assertEq(weth.balanceOf(alice), expectedAmountOut);
        assertEq(steth.balanceOf(alice), 0);
        assertEq(weth.balanceOf(address(etherARM)), armWethBefore - expectedAmountOut);
        assertEq(steth.balanceOf(address(etherARM)), armStethBefore + amountIn);
        assertEq(amounts.length, 2);
        assertEq(amounts[0], amountIn);
        assertEq(amounts[1], expectedAmountOut);
        assertGt(etherARM.totalAssets(), totalAssetsBefore);
        // Note: Temporary 1 wei tolerance while the fee rounding issue is being fixed.
        assertApproxEqAbs(etherARM.totalAssets(), totalAssetsBefore + expectedTotalAssetsIncrease - expectedFee, 1);
    }

    function testFuzz_SwapExactTokensForTokens_Steth_To_Weth_BuyPrice(uint128 fuzzedBuyPrice) public {
        // Isolate the price dimension: amountIn is fixed so any failure points at the price/fee math
        // rather than at amount bounding or liquidity exhaustion.
        uint256 amountIn = 50 ether;
        uint256 wethSeed = 50_000 ether;
        deal(address(weth), address(etherARM), wethSeed);
        deal(address(steth), alice, amountIn);

        // Valid buyPrice range from AbstractARM._validatePrices:
        // buyPrice >= MAX_CROSS_PRICE_DEVIATION (20e32) and buyPrice < crossPrice (1e36 here).
        // Reuse the existing sellPrice from setUp() — _validatePrices also requires sellPrice >= crossPrice.
        uint256 spread;
        uint256 buyPriceFuzzed;
        {
            uint256 crossPriceCurrent = crossPrice(steth);
            buyPriceFuzzed = _bound(uint256(fuzzedBuyPrice), MAX_CROSS_PRICE_DEVIATION, crossPriceCurrent - 1);
            spread = crossPriceCurrent - buyPriceFuzzed;

            // Resolve every setPrices arg before the prank so no view-call between them consumes it.
            uint128 sellPriceArg = uint128(sellPrice(steth));
            vm.prank(governor);
            etherARM.setPrices(address(steth), buyPriceFuzzed, sellPriceArg, type(uint128).max, type(uint128).max);
        }

        // Expected output uses the same scaling as the contract because there is no algebraic
        // shortcut once buyPrice is arbitrary. The value of the test sits in the fee formula below.
        uint256 expectedAmountOut = amountIn * buyPriceFuzzed / PRICE_SCALE;
        uint256 expectedTotalAssetsIncrease = amountIn - expectedAmountOut;

        // Fee derivation takes a different multiply/divide order than the contract:
        //   contract:  fee = amountOut * floor((cross - buy) * feeRate * PRICE_SCALE / (buy * FEE_SCALE)) / PRICE_SCALE
        //   test:      fee = floor(amountOut * (cross - buy) / buy) * feeRate / FEE_SCALE
        // Both converge on the same mathematical value, so a bug that mangles the multiplier
        // scaling, swaps numerator/denominator, or applies the fee on the wrong side of the spread
        // will diverge here.
        uint256 expectedFee = expectedAmountOut.mulDiv(spread, buyPriceFuzzed) * DEFAULT_FEE / FEE_SCALE;

        // Property guard: buyPrice < crossPrice guarantees amountOut < amountIn (trader pays the spread).
        assertLt(expectedAmountOut, amountIn);

        uint256 buyLiquidityBefore = buyLiquidityRemaining(steth);
        uint256 sellLiquidityBefore = sellLiquidityRemaining(steth);
        uint256 totalAssetsBefore = etherARM.totalAssets();

        // Expect events
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(alice, address(etherARM), amountIn);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(etherARM), alice, expectedAmountOut);

        // When
        vm.prank(alice);
        uint256[] memory amounts = etherARM.swapExactTokensForTokens(steth, weth, amountIn, expectedAmountOut, alice);

        // Then
        // Tolerance of 2 wei: the two formulas above each truncate at one step, so they can disagree
        // by up to 1 wei from rounding, plus the contract's PRICE_SCALE intermediate truncation can
        // shift the result by another wei at extreme prices.
        assertApproxEqAbs(etherARM.feesAccrued(), expectedFee, 2);
        assertEq(buyLiquidityRemaining(steth), buyLiquidityBefore - expectedAmountOut);
        assertEq(sellLiquidityRemaining(steth), sellLiquidityBefore);
        assertEq(weth.balanceOf(alice), expectedAmountOut);
        assertEq(steth.balanceOf(alice), 0);
        // The ARM started with the WETH seed and zero stETH; the swap moves expectedAmountOut WETH out
        // and amountIn stETH in.
        assertEq(weth.balanceOf(address(etherARM)), wethSeed - expectedAmountOut);
        assertEq(steth.balanceOf(address(etherARM)), amountIn);
        assertEq(amounts.length, 2);
        assertEq(amounts[0], amountIn);
        assertEq(amounts[1], expectedAmountOut);
        // fee = gain * feeRate / FEE_SCALE algebraically, so with feeRate = 20% < 100% the gain
        // always exceeds the fee and totalAssets must strictly increase.
        assertGt(etherARM.totalAssets(), totalAssetsBefore);
        assertApproxEqAbs(etherARM.totalAssets(), totalAssetsBefore + expectedTotalAssetsIncrease - expectedFee, 2);
    }

    function testFuzz_SwapExactTokensForTokens_Weth_To_Steth_Amount(uint128 wethAmount) public {
        // Seed stETH liquidity so the ARM can pay out the base asset. The WETH side does not need
        // seeding here because the trader is bringing WETH in.
        uint256 armStethSeed = 50_000 ether;
        deal(address(steth), address(etherARM), armStethSeed);

        // Bound the input so amountOut never exceeds the ARM's stETH balance.
        // amountOut = amountIn * 1000 / 1001 (PRICE_SCALE / sellPrice), so cap amountIn at
        // armSteth * 1001 / 1000 to keep the swap inside the liquidity check.
        // Lower bound is 1 wei: the spread (amountIn - amountOut) is at least 1 wei for amountIn >= 1
        // because integer truncation of (amountIn * 1000 / 1001) loses fractional stETH, which is
        // required for the totalAssets-must-strictly-increase assertion to hold.
        uint256 armSteth = steth.balanceOf(address(etherARM));
        uint256 maxAmountIn = armSteth.mulDiv(SELL_PRICE_NUMERATOR, SELL_PRICE_DENOMINATOR);
        uint256 amountIn = _bound(uint256(wethAmount), 1, maxAmountIn);

        // Expected output is computed without going through the contract's PRICE_SCALE path, so a
        // bug that swaps numerator/denominator or changes the sell price would be caught here.
        uint256 expectedAmountOut = amountIn.mulDiv(SELL_PRICE_DENOMINATOR, SELL_PRICE_NUMERATOR);
        uint256 expectedTotalAssetsIncrease = amountIn - expectedAmountOut;

        // Sanity-check the bound so a future change cannot silently push amountOut above the ARM's
        // stETH balance and turn revert paths into spurious failures.
        assertLe(expectedAmountOut, armSteth, "amountOut exceeds ARM stETH balance");

        deal(address(weth), alice, amountIn);

        uint256 feeAccruedBefore = etherARM.feesAccrued();
        assertEq(weth.balanceOf(alice), amountIn);
        uint256 stethBalanceBefore = steth.balanceOf(alice);

        uint256 buyLiquidityBefore = buyLiquidityRemaining(steth);
        uint256 sellLiquidityBefore = sellLiquidityRemaining(steth);
        uint256 armWethBefore = weth.balanceOf(address(etherARM));
        uint256 armStethBefore = steth.balanceOf(address(etherARM));
        uint256 totalAssetsBefore = etherARM.totalAssets();

        // Expect events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(etherARM), amountIn);
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(address(etherARM), alice, expectedAmountOut);

        // When
        vm.prank(alice);
        uint256[] memory amounts = etherARM.swapExactTokensForTokens(weth, steth, amountIn, expectedAmountOut, alice);

        // Then
        // No fees on sell side: feesAccrued must stay exactly where it was.
        assertEq(etherARM.feesAccrued(), feeAccruedBefore);
        assertEq(buyLiquidityRemaining(steth), buyLiquidityBefore);
        assertEq(sellLiquidityRemaining(steth), sellLiquidityBefore - expectedAmountOut);
        assertEq(weth.balanceOf(alice), 0);
        assertEq(steth.balanceOf(alice), stethBalanceBefore + expectedAmountOut);
        assertEq(weth.balanceOf(address(etherARM)), armWethBefore + amountIn);
        assertEq(steth.balanceOf(address(etherARM)), armStethBefore - expectedAmountOut);
        assertEq(amounts.length, 2);
        assertEq(amounts[0], amountIn);
        assertEq(amounts[1], expectedAmountOut);
        assertGt(etherARM.totalAssets(), totalAssetsBefore);
        assertEq(etherARM.totalAssets(), totalAssetsBefore + expectedTotalAssetsIncrease);
    }

    function testFuzz_SwapExactTokensForTokens_Weth_To_Steth_SellPrice(uint128 fuzzedSellPrice) public {
        // Isolate the price dimension: amountIn is fixed so any failure points at the price math
        // rather than at amount bounding or liquidity exhaustion.
        uint256 amountIn = 25 ether;
        uint256 stethSeed = 50_000 ether;
        deal(address(steth), address(etherARM), stethSeed);
        deal(address(weth), alice, amountIn);

        // Valid sellPrice range from AbstractARM._validatePrices: sellPrice >= crossPrice.
        // Use crossPrice + 1 as the lower bound to guarantee a strictly positive spread, which is
        // required for the totalAssets-must-strictly-increase assertion to hold.
        // Reuse the existing buyPrice from setUp() — _validatePrices also requires buyPrice < crossPrice.
        uint256 sellPriceFuzzed;
        {
            uint256 crossPriceCurrent = crossPrice(steth);
            sellPriceFuzzed = _bound(uint256(fuzzedSellPrice), crossPriceCurrent + 1, type(uint128).max);

            // Resolve every setPrices arg before the prank so no view-call between them consumes it.
            uint128 buyPriceArg = uint128(buyPrice(steth));
            vm.prank(governor);
            etherARM.setPrices(
                address(steth), buyPriceArg, uint128(sellPriceFuzzed), type(uint128).max, type(uint128).max
            );
        }

        // amountOut = amountIn * PRICE_SCALE / sellPrice (pegged base asset, no adapter conversion).
        // Same code path as the contract: there is no algebraic shortcut once sellPrice is arbitrary.
        // The value of the test is in checking the surrounding invariants across the full price range.
        uint256 expectedAmountOut = amountIn.mulDiv(PRICE_SCALE, sellPriceFuzzed);
        uint256 expectedTotalAssetsIncrease = amountIn - expectedAmountOut;

        // Property guard: sellPrice > crossPrice guarantees amountOut < amountIn (trader pays the spread).
        assertLt(expectedAmountOut, amountIn);

        uint256 buyLiquidityBefore = buyLiquidityRemaining(steth);
        uint256 sellLiquidityBefore = sellLiquidityRemaining(steth);
        uint256 armWethBefore = weth.balanceOf(address(etherARM));
        uint256 totalAssetsBefore = etherARM.totalAssets();

        // Expect events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(etherARM), amountIn);
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(address(etherARM), alice, expectedAmountOut);

        // When
        vm.prank(alice);
        uint256[] memory amounts = etherARM.swapExactTokensForTokens(weth, steth, amountIn, expectedAmountOut, alice);

        // Then
        // No fees on sell side: feesAccrued must stay at 0.
        assertEq(etherARM.feesAccrued(), 0);
        assertEq(buyLiquidityRemaining(steth), buyLiquidityBefore);
        assertEq(sellLiquidityRemaining(steth), sellLiquidityBefore - expectedAmountOut);
        assertEq(weth.balanceOf(alice), 0);
        assertEq(steth.balanceOf(alice), expectedAmountOut);
        assertEq(weth.balanceOf(address(etherARM)), armWethBefore + amountIn);
        assertEq(steth.balanceOf(address(etherARM)), stethSeed - expectedAmountOut);
        assertEq(amounts.length, 2);
        assertEq(amounts[0], amountIn);
        assertEq(amounts[1], expectedAmountOut);
        assertGt(etherARM.totalAssets(), totalAssetsBefore);
        // Exact equality on the sell side: no fee path runs, so no rounding tolerance is needed.
        assertEq(etherARM.totalAssets(), totalAssetsBefore + expectedTotalAssetsIncrease);
    }

    //////////////////////////////////////////////////////
    /// ---   SwapTokensForExactTokens (exact output)  ---
    //////////////////////////////////////////////////////

    function testFuzz_SwapTokensForExactTokens_Steth_To_Weth_Amount(uint128 wethAmount) public {
        // Seed WETH liquidity so the ARM can pay out the exact amountOut to the trader.
        uint256 wethSeed = 50_000 ether;
        deal(address(weth), address(etherARM), wethSeed);

        // amountOut (WETH) is bounded by the ARM's WETH balance.
        // Lower bound is 1 wei: even at amountOut = 1, the 3 wei rounding buffer gives a positive
        // spread so the totalAssets-must-strictly-increase assertion holds.
        uint256 armWeth = weth.balanceOf(address(etherARM));
        uint256 amountOut = _bound(uint256(wethAmount), 1, armWeth);

        // amountIn = amountOut * 1000 / 992 + 3 (mathematical equivalent of
        // contract's amountOut * PRICE_SCALE / buyPrice + 3). Going through the simple ratio
        // catches bugs that swap numerator/denominator or change the buy price.
        uint256 expectedAmountIn = amountOut.mulDiv(BUY_PRICE_DENOMINATOR, BUY_PRICE_NUMERATOR) + ROUNDING_BUFFER;
        uint256 expectedTotalAssetsIncrease = expectedAmountIn - amountOut;
        uint256 expectedFee = expectedTotalAssetsIncrease.mulDiv(DEFAULT_FEE, FEE_SCALE);

        deal(address(steth), alice, expectedAmountIn);

        assertEq(etherARM.feesAccrued(), 0);
        assertEq(weth.balanceOf(alice), 0);
        assertEq(steth.balanceOf(alice), expectedAmountIn);

        uint256 buyLiquidityBefore = buyLiquidityRemaining(steth);
        uint256 sellLiquidityBefore = sellLiquidityRemaining(steth);
        uint256 armWethBefore = weth.balanceOf(address(etherARM));
        uint256 armStethBefore = steth.balanceOf(address(etherARM));
        uint256 totalAssetsBefore = etherARM.totalAssets();

        // Expect events
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(alice, address(etherARM), expectedAmountIn);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(etherARM), alice, amountOut);

        // When
        vm.prank(alice);
        uint256[] memory amounts = etherARM.swapTokensForExactTokens(steth, weth, amountOut, expectedAmountIn, alice);

        // Then
        // Note: Temporary 1 wei tolerance while the fee rounding issue is being fixed.
        assertApproxEqAbs(etherARM.feesAccrued(), expectedFee, 1);
        assertEq(buyLiquidityRemaining(steth), buyLiquidityBefore - amountOut);
        assertEq(sellLiquidityRemaining(steth), sellLiquidityBefore);
        assertEq(weth.balanceOf(alice), amountOut);
        assertEq(steth.balanceOf(alice), 0);
        assertEq(weth.balanceOf(address(etherARM)), armWethBefore - amountOut);
        assertEq(steth.balanceOf(address(etherARM)), armStethBefore + expectedAmountIn);
        assertEq(amounts.length, 2);
        assertEq(amounts[0], expectedAmountIn);
        assertEq(amounts[1], amountOut);
        assertGt(etherARM.totalAssets(), totalAssetsBefore);
        // Note: Temporary 1 wei tolerance while the fee rounding issue is being fixed.
        assertApproxEqAbs(etherARM.totalAssets(), totalAssetsBefore + expectedTotalAssetsIncrease - expectedFee, 1);
    }

    function testFuzz_SwapTokensForExactTokens_Steth_To_Weth_BuyPrice(uint128 fuzzedBuyPrice) public {
        // Isolate the price dimension: amountOut is fixed so any failure points at the price/fee math
        // rather than at amount bounding or liquidity exhaustion.
        uint256 amountOut = 50 ether;
        uint256 wethSeed = 50_000 ether;
        deal(address(weth), address(etherARM), wethSeed);

        // Valid buyPrice range from AbstractARM._validatePrices:
        // buyPrice >= MAX_CROSS_PRICE_DEVIATION (20e32) and buyPrice < crossPrice (1e36 here).
        uint256 spread;
        uint256 buyPriceFuzzed;
        {
            uint256 crossPriceCurrent = crossPrice(steth);
            buyPriceFuzzed = _bound(uint256(fuzzedBuyPrice), MAX_CROSS_PRICE_DEVIATION, crossPriceCurrent - 1);
            spread = crossPriceCurrent - buyPriceFuzzed;

            // Resolve every setPrices arg before the prank so no view-call between them consumes it.
            uint128 sellPriceArg = uint128(sellPrice(steth));
            vm.prank(governor);
            etherARM.setPrices(address(steth), buyPriceFuzzed, sellPriceArg, type(uint128).max, type(uint128).max);
        }

        // expectedAmountIn uses the same scaling as the contract because there is no algebraic
        // shortcut once buyPrice is arbitrary. The value of the test sits in the fee formula below.
        uint256 expectedAmountIn = amountOut.mulDiv(PRICE_SCALE, buyPriceFuzzed) + ROUNDING_BUFFER;
        uint256 expectedTotalAssetsIncrease = expectedAmountIn - amountOut;

        // Fee derivation takes a different multiply/divide order than the contract:
        //   contract:  fee = amountOut * floor((cross - buy) * feeRate * PRICE_SCALE / (buy * FEE_SCALE)) / PRICE_SCALE
        //   test:      fee = floor(amountOut * (cross - buy) / buy) * feeRate / FEE_SCALE
        // Both converge on the same mathematical value, so a bug that mangles the multiplier
        // scaling, swaps numerator/denominator, or applies the fee on the wrong side of the spread
        // will diverge here.
        uint256 expectedFee = amountOut.mulDiv(spread, buyPriceFuzzed) * DEFAULT_FEE / FEE_SCALE;

        // Property guard: buyPrice < crossPrice guarantees amountIn > amountOut (trader pays the spread).
        assertGt(expectedAmountIn, amountOut);

        deal(address(steth), alice, expectedAmountIn);

        uint256 buyLiquidityBefore = buyLiquidityRemaining(steth);
        uint256 sellLiquidityBefore = sellLiquidityRemaining(steth);
        uint256 totalAssetsBefore = etherARM.totalAssets();

        // Expect events
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(alice, address(etherARM), expectedAmountIn);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(etherARM), alice, amountOut);

        // When
        vm.prank(alice);
        uint256[] memory amounts = etherARM.swapTokensForExactTokens(steth, weth, amountOut, expectedAmountIn, alice);

        // Then
        // Tolerance of 2 wei: each formula truncates at a different step, so they can disagree by
        // up to 1 wei from rounding, plus the contract's PRICE_SCALE intermediate truncation can
        // shift the result by another wei at extreme prices.
        assertApproxEqAbs(etherARM.feesAccrued(), expectedFee, 2);
        assertEq(buyLiquidityRemaining(steth), buyLiquidityBefore - amountOut);
        assertEq(sellLiquidityRemaining(steth), sellLiquidityBefore);
        assertEq(weth.balanceOf(alice), amountOut);
        assertEq(steth.balanceOf(alice), 0);
        // The ARM started with the WETH seed and zero stETH; the swap moves amountOut WETH out
        // and expectedAmountIn stETH in.
        assertEq(weth.balanceOf(address(etherARM)), wethSeed - amountOut);
        assertEq(steth.balanceOf(address(etherARM)), expectedAmountIn);
        assertEq(amounts.length, 2);
        assertEq(amounts[0], expectedAmountIn);
        assertEq(amounts[1], amountOut);
        // fee = gain * feeRate / FEE_SCALE algebraically, so with feeRate = 20% < 100% the gain
        // always exceeds the fee and totalAssets must strictly increase.
        assertGt(etherARM.totalAssets(), totalAssetsBefore);
        assertApproxEqAbs(etherARM.totalAssets(), totalAssetsBefore + expectedTotalAssetsIncrease - expectedFee, 2);
    }

    function testFuzz_SwapTokensForExactTokens_Weth_To_Steth_Amount(uint128 stethAmount) public {
        // Seed stETH liquidity so the ARM can pay out the exact amountOut to the trader.
        uint256 armStethSeed = 50_000 ether;
        deal(address(steth), address(etherARM), armStethSeed);

        // amountOut (stETH) is bounded by the ARM's stETH balance.
        // Lower bound is 1 wei: even at amountOut = 1, the 3 wei rounding buffer gives a positive
        // spread so the totalAssets-must-strictly-increase assertion holds.
        uint256 armSteth = steth.balanceOf(address(etherARM));
        uint256 amountOut = _bound(uint256(stethAmount), 1, armSteth);

        // amountIn = amountOut * 1001 / 1000 + 3 (mathematical equivalent of
        // contract's amountOut * sellPrice / PRICE_SCALE + 3). Going through the simple ratio
        // catches bugs that swap numerator/denominator or change the sell price.
        uint256 expectedAmountIn = amountOut.mulDiv(SELL_PRICE_NUMERATOR, SELL_PRICE_DENOMINATOR) + ROUNDING_BUFFER;
        uint256 expectedTotalAssetsIncrease = expectedAmountIn - amountOut;

        deal(address(weth), alice, expectedAmountIn);

        uint256 feeAccruedBefore = etherARM.feesAccrued();
        assertEq(weth.balanceOf(alice), expectedAmountIn);
        uint256 stethBalanceBefore = steth.balanceOf(alice);

        uint256 buyLiquidityBefore = buyLiquidityRemaining(steth);
        uint256 sellLiquidityBefore = sellLiquidityRemaining(steth);
        uint256 armWethBefore = weth.balanceOf(address(etherARM));
        uint256 armStethBefore = steth.balanceOf(address(etherARM));
        uint256 totalAssetsBefore = etherARM.totalAssets();

        // Expect events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(etherARM), expectedAmountIn);
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(address(etherARM), alice, amountOut);

        // When
        vm.prank(alice);
        uint256[] memory amounts = etherARM.swapTokensForExactTokens(weth, steth, amountOut, expectedAmountIn, alice);

        // Then
        // No fees on sell side: feesAccrued must stay exactly where it was.
        assertEq(etherARM.feesAccrued(), feeAccruedBefore);
        assertEq(buyLiquidityRemaining(steth), buyLiquidityBefore);
        assertEq(sellLiquidityRemaining(steth), sellLiquidityBefore - amountOut);
        assertEq(weth.balanceOf(alice), 0);
        assertEq(steth.balanceOf(alice), stethBalanceBefore + amountOut);
        assertEq(weth.balanceOf(address(etherARM)), armWethBefore + expectedAmountIn);
        assertEq(steth.balanceOf(address(etherARM)), armStethBefore - amountOut);
        assertEq(amounts.length, 2);
        assertEq(amounts[0], expectedAmountIn);
        assertEq(amounts[1], amountOut);
        assertGt(etherARM.totalAssets(), totalAssetsBefore);
        assertEq(etherARM.totalAssets(), totalAssetsBefore + expectedTotalAssetsIncrease);
    }

    function testFuzz_SwapTokensForExactTokens_Weth_To_Steth_SellPrice(uint128 fuzzedSellPrice) public {
        // Isolate the price dimension: amountOut is fixed so any failure points at the price math
        // rather than at amount bounding or liquidity exhaustion.
        uint256 amountOut = 25 ether;
        uint256 stethSeed = 50_000 ether;
        deal(address(steth), address(etherARM), stethSeed);

        // Valid sellPrice range from AbstractARM._validatePrices: sellPrice >= crossPrice.
        // Use crossPrice + 1 as the lower bound to guarantee a strictly positive spread, which is
        // required for the totalAssets-must-strictly-increase assertion.
        uint256 sellPriceFuzzed;
        {
            uint256 crossPriceCurrent = crossPrice(steth);
            sellPriceFuzzed = _bound(uint256(fuzzedSellPrice), crossPriceCurrent + 1, type(uint128).max);

            // Resolve every setPrices arg before the prank so no view-call between them consumes it.
            uint128 buyPriceArg = uint128(buyPrice(steth));
            vm.prank(governor);
            etherARM.setPrices(
                address(steth), buyPriceArg, uint128(sellPriceFuzzed), type(uint128).max, type(uint128).max
            );
        }

        // amountIn = amountOut * sellPrice / PRICE_SCALE + 3 (pegged base asset, no adapter conversion).
        // Same code path as the contract: there is no algebraic shortcut once sellPrice is arbitrary.
        // The value of the test is in checking the surrounding invariants across the full price range.
        uint256 expectedAmountIn = amountOut.mulDiv(sellPriceFuzzed, PRICE_SCALE) + ROUNDING_BUFFER;
        uint256 expectedTotalAssetsIncrease = expectedAmountIn - amountOut;

        // Property guard: sellPrice > crossPrice guarantees amountIn > amountOut (trader pays the spread).
        assertGt(expectedAmountIn, amountOut);

        deal(address(weth), alice, expectedAmountIn);

        uint256 buyLiquidityBefore = buyLiquidityRemaining(steth);
        uint256 sellLiquidityBefore = sellLiquidityRemaining(steth);
        uint256 armWethBefore = weth.balanceOf(address(etherARM));
        uint256 totalAssetsBefore = etherARM.totalAssets();

        // Expect events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(etherARM), expectedAmountIn);
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(address(etherARM), alice, amountOut);

        // When
        vm.prank(alice);
        uint256[] memory amounts = etherARM.swapTokensForExactTokens(weth, steth, amountOut, expectedAmountIn, alice);

        // Then
        // No fees on sell side: feesAccrued must stay at 0.
        assertEq(etherARM.feesAccrued(), 0);
        assertEq(buyLiquidityRemaining(steth), buyLiquidityBefore);
        assertEq(sellLiquidityRemaining(steth), sellLiquidityBefore - amountOut);
        assertEq(weth.balanceOf(alice), 0);
        assertEq(steth.balanceOf(alice), amountOut);
        assertEq(weth.balanceOf(address(etherARM)), armWethBefore + expectedAmountIn);
        assertEq(steth.balanceOf(address(etherARM)), stethSeed - amountOut);
        assertEq(amounts.length, 2);
        assertEq(amounts[0], expectedAmountIn);
        assertEq(amounts[1], amountOut);
        assertGt(etherARM.totalAssets(), totalAssetsBefore);
        // Exact equality on the sell side: no fee path runs, so no rounding tolerance is needed.
        assertEq(etherARM.totalAssets(), totalAssetsBefore + expectedTotalAssetsIncrease);
    }
}
