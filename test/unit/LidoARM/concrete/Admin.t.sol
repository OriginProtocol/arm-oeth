// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_LidoARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";
import {Ownable} from "contracts/Ownable.sol";
import {OwnableOperable} from "contracts/OwnableOperable.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Mocks
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

/// @notice Unit tests for the LidoARM admin surface — every owner / operator setter,
///         covering the happy path AND each documented revert branch. Wherever a
///         function does anything beyond writing a single field (event emission,
///         approvals, internal validation, side-effect calls into related state),
///         the happy-path test asserts that side effect explicitly so the test
///         catches removal of any of those behaviors.
contract Unit_LidoARM_Admin_Test is Unit_LidoARM_Shared_Test {
    // Valid price defaults inside the [PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION, PRICE_SCALE] band.
    uint256 internal constant CROSS_PRICE_DEFAULT = 1e36;
    uint256 internal constant BUY_PRICE_DEFAULT = 992 * 1e33; // 0.992e36
    uint256 internal constant SELL_PRICE_DEFAULT = 1001 * 1e33; // 1.001e36
    uint256 internal constant LIQUIDITY_DEFAULT = type(uint128).max;

    function setUp() public override {
        super.setUp();
    }

    /// @dev Drive `feesAccrued` to a non-zero value via the real swap path so the fee tests
    ///      exercise the same accrual logic that production callers hit. Setup: register stETH
    ///      with the default 0.992 buy price + 20% fee, seed alice with stETH, swap 10 stETH
    ///      worth for WETH out — the spread between cross and buy is the fee. Returns the
    ///      actual accrued amount so callers don't need to recompute it.
    function _accrueFeesViaSwap() internal returns (uint256 accrued) {
        desactiveCapManager(); // default total-assets cap is 0; disable so the deposit can land
        addBaseAsset(steth);
        aliceFirstDeposit(100 ether); // ARM now holds 100 ether of WETH available to swap out

        uint256 amountOut = 10 ether;
        // amountIn rounding mirrors AbstractARM._swapTokensForExactTokens: amountOut * PRICE_SCALE / buyPrice + 3 wei.
        uint256 expectedAmountIn = amountOut * PRICE_SCALE / BUY_PRICE_DEFAULT + 3;
        deal(address(steth), alice, expectedAmountIn);

        vm.prank(alice);
        lidoARM.swapTokensForExactTokens(steth, weth, amountOut, expectedAmountIn, alice);

        accrued = lidoARM.feesAccrued();
        require(accrued > 0, "test setup: swap did not accrue fees");
    }

    //////////////////////////////////////////////////////
    /// --- addBaseAsset
    //////////////////////////////////////////////////////

    function test_AddBaseAsset_Default() public {
        // Pre: stETH not yet registered, no allowance from ARM to adapter.
        (,,,,,,,, address adapterBefore) = lidoARM.baseAssetConfigs(address(steth));
        assertEq(adapterBefore, address(0), "adapter unset pre");
        assertEq(steth.allowance(address(lidoARM), address(stETHAssetAdapter)), 0, "no allowance pre");

        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.BaseAssetAdded(
            address(steth), address(stETHAssetAdapter), BUY_PRICE_DEFAULT, SELL_PRICE_DEFAULT, CROSS_PRICE_DEFAULT, true
        );

        vm.prank(governor);
        lidoARM.addBaseAsset(
            address(steth),
            address(stETHAssetAdapter),
            BUY_PRICE_DEFAULT,
            SELL_PRICE_DEFAULT,
            LIQUIDITY_DEFAULT,
            LIQUIDITY_DEFAULT,
            CROSS_PRICE_DEFAULT,
            true
        );

        // Storage written
        (
            uint128 buyP,
            uint128 sellP,
            uint128 buyLiq,
            uint128 sellLiq,
            uint128 crossP,
            uint128 pendingRedeem,
            bool pegged,
            uint8 baseDec,
            address adapter
        ) = lidoARM.baseAssetConfigs(address(steth));
        assertEq(buyP, BUY_PRICE_DEFAULT, "buyPrice");
        assertEq(sellP, SELL_PRICE_DEFAULT, "sellPrice");
        assertEq(buyLiq, LIQUIDITY_DEFAULT, "buyLiquidityRemaining");
        assertEq(sellLiq, LIQUIDITY_DEFAULT, "sellLiquidityRemaining");
        assertEq(crossP, CROSS_PRICE_DEFAULT, "crossPrice");
        assertEq(pendingRedeem, 0, "pendingRedeemAssets reset to 0");
        assertTrue(pegged, "peggedToLiquidityAsset");
        assertEq(baseDec, 18, "baseAssetDecimals");
        assertEq(adapter, address(stETHAssetAdapter), "adapter");

        // Side effect: ARM approves the adapter for max stETH so requestRedeem can pull.
        assertEq(
            steth.allowance(address(lidoARM), address(stETHAssetAdapter)),
            type(uint256).max,
            "ARM stETH allowance to adapter"
        );
    }

    function test_AddBaseAsset_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        lidoARM.addBaseAsset(
            address(steth),
            address(stETHAssetAdapter),
            BUY_PRICE_DEFAULT,
            SELL_PRICE_DEFAULT,
            LIQUIDITY_DEFAULT,
            LIQUIDITY_DEFAULT,
            CROSS_PRICE_DEFAULT,
            true
        );
    }

    function test_AddBaseAsset_RevertWhen_AssetIsZero() public {
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidAsset.selector);
        lidoARM.addBaseAsset(
            address(0),
            address(stETHAssetAdapter),
            BUY_PRICE_DEFAULT,
            SELL_PRICE_DEFAULT,
            LIQUIDITY_DEFAULT,
            LIQUIDITY_DEFAULT,
            CROSS_PRICE_DEFAULT,
            true
        );
    }

    function test_AddBaseAsset_RevertWhen_AdapterIsZero() public {
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidAdapter.selector);
        lidoARM.addBaseAsset(
            address(steth),
            address(0),
            BUY_PRICE_DEFAULT,
            SELL_PRICE_DEFAULT,
            LIQUIDITY_DEFAULT,
            LIQUIDITY_DEFAULT,
            CROSS_PRICE_DEFAULT,
            true
        );
    }

    function test_AddBaseAsset_RevertWhen_AssetAlreadySupported() public {
        addBaseAsset(steth); // first registration via shared helper

        vm.prank(governor);
        vm.expectRevert(AbstractARM.AssetAlreadySupported.selector);
        lidoARM.addBaseAsset(
            address(steth),
            address(stETHAssetAdapter),
            BUY_PRICE_DEFAULT,
            SELL_PRICE_DEFAULT,
            LIQUIDITY_DEFAULT,
            LIQUIDITY_DEFAULT,
            CROSS_PRICE_DEFAULT,
            true
        );
    }

    function test_AddBaseAsset_RevertWhen_InvalidAssetDecimals() public {
        // 8-decimal token: the ARM only accepts base assets with 6 or 18 decimals.
        IERC20 badDecimals = IERC20(address(new MockERC20("BAD8", "BAD8", 8)));

        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidAssetDecimals.selector);
        lidoARM.addBaseAsset(
            address(badDecimals),
            address(stETHAssetAdapter),
            BUY_PRICE_DEFAULT,
            SELL_PRICE_DEFAULT,
            LIQUIDITY_DEFAULT,
            LIQUIDITY_DEFAULT,
            CROSS_PRICE_DEFAULT,
            true
        );
    }

    function test_AddBaseAsset_RevertWhen_AdapterAssetMismatch() public {
        // mockWstETH (ERC4626 of stETH) has `asset() == steth`, which is NOT the ARM's
        // liquidityAsset (weth). The cast through IAssetAdapter.asset() still succeeds because the
        // signature matches, but the ARM rejects the mismatch.
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidAdapterAsset.selector);
        lidoARM.addBaseAsset(
            address(steth),
            address(mockWstETH),
            BUY_PRICE_DEFAULT,
            SELL_PRICE_DEFAULT,
            LIQUIDITY_DEFAULT,
            LIQUIDITY_DEFAULT,
            CROSS_PRICE_DEFAULT,
            true
        );
    }

    function test_AddBaseAsset_RevertWhen_CrossPriceTooLow() public {
        // PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION = 1e36 - 20e32 = 0.998e36. One wei below reverts.
        uint256 tooLow = PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION - 1;
        vm.prank(governor);
        vm.expectRevert(AbstractARM.CrossPriceTooLow.selector);
        lidoARM.addBaseAsset(
            address(steth),
            address(stETHAssetAdapter),
            BUY_PRICE_DEFAULT,
            SELL_PRICE_DEFAULT,
            LIQUIDITY_DEFAULT,
            LIQUIDITY_DEFAULT,
            tooLow,
            true
        );
    }

    function test_AddBaseAsset_RevertWhen_CrossPriceTooHigh() public {
        // Cross price strictly above PRICE_SCALE (= 1e36) reverts. Equality is allowed.
        vm.prank(governor);
        vm.expectRevert(AbstractARM.CrossPriceTooHigh.selector);
        lidoARM.addBaseAsset(
            address(steth),
            address(stETHAssetAdapter),
            BUY_PRICE_DEFAULT,
            SELL_PRICE_DEFAULT,
            LIQUIDITY_DEFAULT,
            LIQUIDITY_DEFAULT,
            PRICE_SCALE + 1,
            true
        );
    }

    function test_AddBaseAsset_RevertWhen_SellPriceBelowCross() public {
        // sellPrice < crossPrice is rejected by _validatePrices.
        vm.prank(governor);
        vm.expectRevert(AbstractARM.SellPriceTooLow.selector);
        lidoARM.addBaseAsset(
            address(steth),
            address(stETHAssetAdapter),
            BUY_PRICE_DEFAULT,
            CROSS_PRICE_DEFAULT - 1, // sell < cross
            LIQUIDITY_DEFAULT,
            LIQUIDITY_DEFAULT,
            CROSS_PRICE_DEFAULT,
            true
        );
    }

    function test_AddBaseAsset_RevertWhen_BuyPriceBelowMinimum() public {
        // _validatePrices: buyPrice < MAX_CROSS_PRICE_DEVIATION (= 20e32) reverts.
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidBuyPrice.selector);
        lidoARM.addBaseAsset(
            address(steth),
            address(stETHAssetAdapter),
            MAX_CROSS_PRICE_DEVIATION - 1,
            SELL_PRICE_DEFAULT,
            LIQUIDITY_DEFAULT,
            LIQUIDITY_DEFAULT,
            CROSS_PRICE_DEFAULT,
            true
        );
    }

    function test_AddBaseAsset_RevertWhen_BuyPriceAtOrAboveCross() public {
        // _validatePrices: buyPrice >= crossPrice reverts. Use equality (the strict-inequality edge).
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidBuyPrice.selector);
        lidoARM.addBaseAsset(
            address(steth),
            address(stETHAssetAdapter),
            CROSS_PRICE_DEFAULT,
            SELL_PRICE_DEFAULT,
            LIQUIDITY_DEFAULT,
            LIQUIDITY_DEFAULT,
            CROSS_PRICE_DEFAULT,
            true
        );
    }

    //////////////////////////////////////////////////////
    /// --- getBaseAssets
    //////////////////////////////////////////////////////

    function test_GetBaseAssets_EmptyByDefault() public view {
        // No base asset registered yet, so the list is empty.
        address[] memory assets = lidoARM.getBaseAssets();
        assertEq(assets.length, 0, "no base assets registered");
    }

    function test_GetBaseAssets_SingleAsset() public {
        addBaseAsset(steth);

        address[] memory assets = lidoARM.getBaseAssets();
        assertEq(assets.length, 1, "one base asset registered");
        assertEq(assets[0], address(steth), "first base asset is stETH");
    }

    function test_GetBaseAssets_MultipleAssets_PreservesInsertionOrder() public {
        addBaseAsset(steth);
        addBaseAsset(wsteth);

        // The list mirrors the storage array, so it reflects registration order.
        address[] memory assets = lidoARM.getBaseAssets();
        assertEq(assets.length, 2, "two base assets registered");
        assertEq(assets[0], address(steth), "first base asset is stETH");
        assertEq(assets[1], address(wsteth), "second base asset is wstETH");
    }

    //////////////////////////////////////////////////////
    /// --- setPrices
    //////////////////////////////////////////////////////

    function test_SetPrices_Owner() public {
        addBaseAsset(steth);

        uint256 newBuy = 0.993e36;
        uint256 newSell = 1.002e36;
        uint256 newBuyLiq = 1_000 ether;
        uint256 newSellLiq = 2_000 ether;

        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.TraderateChanged(address(steth), newBuy, newSell, newBuyLiq, newSellLiq);

        vm.prank(governor);
        lidoARM.setPrices(address(steth), newBuy, newSell, newBuyLiq, newSellLiq);

        assertEq(buyPrice(steth), newBuy, "buyPrice");
        assertEq(sellPrice(steth), newSell, "sellPrice");
        assertEq(buyLiquidityRemaining(steth), newBuyLiq, "buyLiquidityRemaining");
        assertEq(sellLiquidityRemaining(steth), newSellLiq, "sellLiquidityRemaining");
    }

    function test_SetPrices_Operator() public {
        // Operator is the dual-authority role; assert it can update prices just like the owner.
        addBaseAsset(steth);

        vm.prank(operator);
        lidoARM.setPrices(address(steth), 0.994e36, 1.003e36, 1 ether, 2 ether);

        assertEq(buyPrice(steth), 0.994e36, "buyPrice after operator update");
    }

    function test_SetPrices_RevertWhen_NotAuthorized() public {
        addBaseAsset(steth);

        vm.prank(alice);
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        lidoARM.setPrices(address(steth), BUY_PRICE_DEFAULT, SELL_PRICE_DEFAULT, 1 ether, 1 ether);
    }

    function test_SetPrices_RevertWhen_UnsupportedAsset() public {
        // No addBaseAsset → adapter is the zero address.
        vm.prank(governor);
        vm.expectRevert(AbstractARM.UnsupportedAsset.selector);
        lidoARM.setPrices(address(steth), BUY_PRICE_DEFAULT, SELL_PRICE_DEFAULT, 1 ether, 1 ether);
    }

    function test_SetPrices_RevertWhen_SellBelowCross() public {
        addBaseAsset(steth);
        vm.prank(governor);
        vm.expectRevert(AbstractARM.SellPriceTooLow.selector);
        lidoARM.setPrices(address(steth), BUY_PRICE_DEFAULT, CROSS_PRICE_DEFAULT - 1, 1 ether, 1 ether);
    }

    function test_SetPrices_RevertWhen_BuyBelowMinimum() public {
        addBaseAsset(steth);
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidBuyPrice.selector);
        lidoARM.setPrices(address(steth), MAX_CROSS_PRICE_DEVIATION - 1, SELL_PRICE_DEFAULT, 1 ether, 1 ether);
    }

    function test_SetPrices_RevertWhen_BuyAtOrAboveCross() public {
        addBaseAsset(steth);
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidBuyPrice.selector);
        lidoARM.setPrices(address(steth), CROSS_PRICE_DEFAULT, SELL_PRICE_DEFAULT, 1 ether, 1 ether);
    }

    //////////////////////////////////////////////////////
    /// --- setCrossPrice
    //////////////////////////////////////////////////////

    function test_SetCrossPrice_Lower_WithoutExposure() public {
        addBaseAsset(steth);
        // No stETH balance, no pendingRedeem → the lowering-only exposure check is skipped.

        uint256 newCross = 0.999e36;
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.CrossPriceUpdated(address(steth), newCross);

        vm.prank(governor);
        lidoARM.setCrossPrice(address(steth), newCross);

        assertEq(crossPrice(steth), newCross, "crossPrice lowered");
    }

    function test_SetCrossPrice_Raise() public {
        addBaseAsset(steth);

        // Lower first so we can raise back up. (At default, cross == PRICE_SCALE which is the ceiling.)
        vm.prank(governor);
        lidoARM.setCrossPrice(address(steth), 0.999e36);

        vm.prank(governor);
        lidoARM.setCrossPrice(address(steth), PRICE_SCALE);

        assertEq(crossPrice(steth), PRICE_SCALE, "crossPrice raised back to PRICE_SCALE");
    }

    function test_SetCrossPrice_RevertWhen_NotOwner() public {
        addBaseAsset(steth);
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        lidoARM.setCrossPrice(address(steth), 0.999e36);
    }

    function test_SetCrossPrice_RevertWhen_UnsupportedAsset() public {
        vm.prank(governor);
        vm.expectRevert(AbstractARM.UnsupportedAsset.selector);
        lidoARM.setCrossPrice(address(steth), CROSS_PRICE_DEFAULT);
    }

    function test_SetCrossPrice_RevertWhen_TooLow() public {
        addBaseAsset(steth);
        vm.prank(governor);
        vm.expectRevert(AbstractARM.CrossPriceTooLow.selector);
        lidoARM.setCrossPrice(address(steth), PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION - 1);
    }

    function test_SetCrossPrice_RevertWhen_TooHigh() public {
        addBaseAsset(steth);
        vm.prank(governor);
        vm.expectRevert(AbstractARM.CrossPriceTooHigh.selector);
        lidoARM.setCrossPrice(address(steth), PRICE_SCALE + 1);
    }

    function test_SetCrossPrice_RevertWhen_SellBelowNewCross() public {
        addBaseAsset(steth);

        // Step 1: drop cross down to the floor so we can drop sell below 1e36.
        vm.prank(governor);
        lidoARM.setCrossPrice(address(steth), PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION);
        // Step 2: bring sell to a value below PRICE_SCALE (within the new cross floor).
        vm.prank(governor);
        lidoARM.setPrices(address(steth), BUY_PRICE_DEFAULT, PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION, 1 ether, 1 ether);
        // Step 3: raising cross above the new sell triggers the guard.
        vm.prank(governor);
        vm.expectRevert(AbstractARM.SellPriceTooLow.selector);
        lidoARM.setCrossPrice(address(steth), 0.999e36);
    }

    function test_SetCrossPrice_RevertWhen_BuyAtOrAboveNewCross() public {
        addBaseAsset(steth);

        // Raise buy close to cross so a tiny lowering of cross collides with it.
        vm.prank(governor);
        lidoARM.setPrices(address(steth), 0.999e36, SELL_PRICE_DEFAULT, 1 ether, 1 ether);

        // newCross == buyPrice triggers buyPrice >= newCrossPrice.
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidBuyPrice.selector);
        lidoARM.setCrossPrice(address(steth), 0.999e36);
    }

    function test_SetCrossPrice_RevertWhen_TooManyBaseAssets() public {
        addBaseAsset(steth);

        // Park enough stETH on the ARM that, valued at the cross price, exposure >= MIN_TOTAL_SUPPLY.
        // MIN_TOTAL_SUPPLY == 1e12; stETH is valued 1:1 at cross == 1e36, so any balance >= 1e12 wei
        // hits the guard. Deal a generous amount so the inequality is unambiguous.
        deal(address(steth), address(lidoARM), 1 ether);

        vm.prank(governor);
        vm.expectRevert(AbstractARM.TooManyBaseAssets.selector);
        lidoARM.setCrossPrice(address(steth), 0.999e36);
    }

    //////////////////////////////////////////////////////
    /// --- setFee
    //////////////////////////////////////////////////////

    function test_SetFee_Default() public {
        uint256 newFee = 1_500; // 15%

        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.FeeUpdated(newFee);

        vm.prank(governor);
        lidoARM.setFee(newFee);

        assertEq(lidoARM.fee(), newFee, "fee updated");
    }

    function test_SetFee_FlushesAccruedFees() public {
        // _setFee calls collectFees() internally — accrued fees must flow to the collector before
        // the rate changes. Trigger the accrual through a real swap (no storage poking).
        uint256 accrued = _accrueFeesViaSwap();
        uint256 collectorBefore = weth.balanceOf(feeCollector);

        vm.prank(governor);
        lidoARM.setFee(500);

        assertEq(lidoARM.feesAccrued(), 0, "feesAccrued zeroed");
        assertEq(weth.balanceOf(feeCollector) - collectorBefore, accrued, "collector received accrued");
        assertEq(lidoARM.fee(), 500, "fee updated after flush");
    }

    function test_SetFee_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        lidoARM.setFee(100);
    }

    function test_SetFee_RevertWhen_FeeTooHigh() public {
        // Maximum allowed fee is 50% (FEE_SCALE / 2 == 5_000).
        vm.prank(governor);
        vm.expectRevert(AbstractARM.FeeTooHigh.selector);
        lidoARM.setFee(FEE_SCALE / 2 + 1);
    }

    //////////////////////////////////////////////////////
    /// --- setFeeCollector
    //////////////////////////////////////////////////////

    function test_SetFeeCollector_Default() public {
        address newCollector = makeAddr("newCollector");

        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.FeeCollectorUpdated(newCollector);

        vm.prank(governor);
        lidoARM.setFeeCollector(newCollector);

        assertEq(lidoARM.feeCollector(), newCollector, "feeCollector updated");
    }

    function test_SetFeeCollector_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        lidoARM.setFeeCollector(makeAddr("rejected"));
    }

    function test_SetFeeCollector_RevertWhen_ZeroAddress() public {
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidFeeCollector.selector);
        lidoARM.setFeeCollector(address(0));
    }

    //////////////////////////////////////////////////////
    /// --- collectFees
    //////////////////////////////////////////////////////

    function test_CollectFees_ZeroAccrued_ReturnsZeroNoTransfer() public {
        assertEq(lidoARM.feesAccrued(), 0, "feesAccrued starts at 0");
        uint256 collectorBefore = weth.balanceOf(feeCollector);

        uint256 collected = lidoARM.collectFees();

        assertEq(collected, 0, "returns 0 when nothing accrued");
        assertEq(weth.balanceOf(feeCollector), collectorBefore, "no transfer when 0 accrued");
    }

    function test_CollectFees_NonZero_TransfersToCollector() public {
        uint256 accrued = _accrueFeesViaSwap();
        uint256 collectorBefore = weth.balanceOf(feeCollector);

        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.FeeCollected(feeCollector, accrued);

        uint256 collected = lidoARM.collectFees();

        assertEq(collected, accrued, "returns accrued amount");
        assertEq(lidoARM.feesAccrued(), 0, "feesAccrued zeroed");
        assertEq(weth.balanceOf(feeCollector) - collectorBefore, accrued, "collector received");
    }

    function test_CollectFees_RevertWhen_InsufficientLiquidity() public {
        // Natural setup for the guard: accrue some fees via a real swap, then reserve most of
        // the ARM's WETH for an LP withdrawal so `reservedWithdrawLiquidity + fees` exceeds the
        // on-hand WETH balance.
        _accrueFeesViaSwap();

        // After the swap the ARM holds ~90 ether of WETH; reserving 95 ether of shares pushes
        // reservedWithdrawLiquidity past the balance even before the (small) fee is added.
        vm.prank(alice);
        lidoARM.requestRedeem(95 ether);

        vm.expectRevert("ARM: Insufficient liquidity");
        lidoARM.collectFees();
    }

    //////////////////////////////////////////////////////
    /// --- setCapManager
    //////////////////////////////////////////////////////

    function test_SetCapManager_ToNonZero() public {
        address newCapManager = makeAddr("newCapManager");

        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.CapManagerUpdated(newCapManager);

        vm.prank(governor);
        lidoARM.setCapManager(newCapManager);

        assertEq(lidoARM.capManager(), newCapManager, "capManager updated");
    }

    function test_SetCapManager_ToZero_DisablesCaps() public {
        // Documented behavior: passing the zero address disables caps without further checks.
        vm.prank(governor);
        lidoARM.setCapManager(address(0));
        assertEq(lidoARM.capManager(), address(0), "capManager cleared");
    }

    function test_SetCapManager_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        lidoARM.setCapManager(makeAddr("rejected"));
    }

    //////////////////////////////////////////////////////
    /// --- setARMBuffer
    //////////////////////////////////////////////////////

    function test_SetARMBuffer_Owner() public {
        uint256 newBuffer = 0.25e18; // 25%

        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.ARMBufferUpdated(newBuffer);

        vm.prank(governor);
        lidoARM.setARMBuffer(newBuffer);

        assertEq(lidoARM.armBuffer(), newBuffer, "armBuffer updated by owner");
    }

    function test_SetARMBuffer_Operator() public {
        vm.prank(operator);
        lidoARM.setARMBuffer(0.5e18);
        assertEq(lidoARM.armBuffer(), 0.5e18, "armBuffer updated by operator");
    }

    function test_SetARMBuffer_BoundaryMax() public {
        // 100% is the inclusive upper bound (1e18).
        vm.prank(governor);
        lidoARM.setARMBuffer(1e18);
        assertEq(lidoARM.armBuffer(), 1e18, "armBuffer at boundary 1e18");
    }

    function test_SetARMBuffer_RevertWhen_NotAuthorized() public {
        vm.prank(alice);
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        lidoARM.setARMBuffer(0.1e18);
    }

    function test_SetARMBuffer_RevertWhen_AboveMax() public {
        // 100% + 1 wei reverts; the guard is strictly `> 1e18`.
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidARMBuffer.selector);
        lidoARM.setARMBuffer(1e18 + 1);
    }
}
