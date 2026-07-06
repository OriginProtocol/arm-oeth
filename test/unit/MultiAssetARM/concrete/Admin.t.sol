// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_MultiAssetARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";
import {Ownable} from "contracts/Ownable.sol";
import {OwnableOperable} from "contracts/OwnableOperable.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Mocks
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MockAssetAdapter} from "../mocks/MockAssetAdapter.sol";

/// @notice Unit tests for the MultiAssetARM admin surface — every owner / operator setter,
///         covering the happy path AND each documented revert branch. Wherever a
///         function does anything beyond writing a single field (event emission,
///         approvals, internal validation, side-effect calls into related state),
///         the happy-path test asserts that side effect explicitly so the test
///         catches removal of any of those behaviors.
contract Unit_MultiAssetARM_Admin_Test is Unit_MultiAssetARM_Shared_Test {
    // Valid price defaults inside the [PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION, PRICE_SCALE] band.
    uint256 internal constant CROSS_PRICE_DEFAULT = 1e36;
    uint256 internal constant BUY_PRICE_DEFAULT = 992 * 1e33; // 0.992e36
    uint256 internal constant SELL_PRICE_DEFAULT = 1001 * 1e33; // 1.001e36
    uint256 internal constant LIQUIDITY_DEFAULT = type(uint128).max;

    function setUp() public override {
        super.setUp();
    }

    /// @dev Admin/base-asset-management tests start from a clean slate and register on demand.
    function _registerInitialBaseAssets() internal override {}

    /// @dev Shared registration helper (mirrors the old EtherARM harness): registers an analog base asset
    ///      with the default prices the tests assert against. peg18 is pegged (stETH analog), adp18 is
    ///      adapter-backed (wstETH analog).
    function addBaseAsset(IERC20 token) internal {
        vm.prank(governor);
        if (token == peg18) {
            arm.addBaseAsset(
                address(peg18),
                address(adapterPeg18),
                BUY_PRICE_DEFAULT,
                SELL_PRICE_DEFAULT,
                LIQUIDITY_DEFAULT,
                LIQUIDITY_DEFAULT,
                CROSS_PRICE_DEFAULT,
                true
            );
        } else if (token == adp18) {
            arm.addBaseAsset(
                address(adp18),
                address(adapterAdp18),
                BUY_PRICE_DEFAULT,
                SELL_PRICE_DEFAULT,
                LIQUIDITY_DEFAULT,
                LIQUIDITY_DEFAULT,
                CROSS_PRICE_DEFAULT,
                false
            );
        } else {
            revert("unsupported base asset");
        }
    }

    /// @dev Drive `feesAccrued` to a non-zero value via the real swap path so the fee tests
    ///      exercise the same accrual logic that production callers hit. Setup: register stETH
    ///      with the default 0.992 buy price + 20% fee, seed alice with stETH, swap 10 stETH
    ///      worth for WETH out — the spread between cross and buy is the fee. Returns the
    ///      actual accrued amount so callers don't need to recompute it.
    function _accrueFeesViaSwap() internal returns (uint256 accrued) {
        desactiveCapManager(); // default total-assets cap is 0; disable so the deposit can land
        addBaseAsset(peg18);
        aliceFirstDeposit(100 ether); // ARM now holds 100 ether of WETH available to swap out

        uint256 amountOut = 10 ether;
        // amountIn rounding mirrors AbstractARM._swapTokensForExactTokens: amountOut * PRICE_SCALE / buyPrice + 3 wei.
        uint256 expectedAmountIn = amountOut * PRICE_SCALE / BUY_PRICE_DEFAULT + 3;
        deal(address(peg18), alice, expectedAmountIn);

        vm.prank(alice);
        arm.swapTokensForExactTokens(peg18, liquidity, amountOut, expectedAmountIn, alice);

        accrued = arm.feesAccrued();
        require(accrued > 0, "test setup: swap did not accrue fees");
    }

    //////////////////////////////////////////////////////
    /// --- addBaseAsset
    //////////////////////////////////////////////////////

    function test_AddBaseAsset_Default() public {
        // Pre: stETH not yet registered, no allowance from ARM to adapter.
        (,,,,,,,, address adapterBefore) = arm.baseAssetConfigs(address(peg18));
        assertEq(adapterBefore, address(0), "adapter unset pre");
        assertEq(peg18.allowance(address(arm), address(adapterPeg18)), 0, "no allowance pre");

        vm.expectEmit({emitter: address(arm)});
        emit AbstractARM.BaseAssetAdded(
            address(peg18), address(adapterPeg18), BUY_PRICE_DEFAULT, SELL_PRICE_DEFAULT, CROSS_PRICE_DEFAULT, true
        );

        vm.prank(governor);
        arm.addBaseAsset(
            address(peg18),
            address(adapterPeg18),
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
            bool isPegged,
            uint8 baseDec,
            address adapter
        ) = arm.baseAssetConfigs(address(peg18));
        assertEq(buyP, BUY_PRICE_DEFAULT, "buyPrice");
        assertEq(sellP, SELL_PRICE_DEFAULT, "sellPrice");
        assertEq(buyLiq, LIQUIDITY_DEFAULT, "buyLiquidityRemaining");
        assertEq(sellLiq, LIQUIDITY_DEFAULT, "sellLiquidityRemaining");
        assertEq(crossP, CROSS_PRICE_DEFAULT, "crossPrice");
        assertEq(pendingRedeem, 0, "pendingRedeemAssets reset to 0");
        assertTrue(isPegged, "peggedToLiquidityAsset");
        assertEq(baseDec, 18, "baseAssetDecimals");
        assertEq(adapter, address(adapterPeg18), "adapter");

        // Side effect: ARM approves the adapter for max stETH so requestRedeem can pull.
        assertEq(
            peg18.allowance(address(arm), address(adapterPeg18)), type(uint256).max, "ARM stETH allowance to adapter"
        );
    }

    function test_AddBaseAsset_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        arm.addBaseAsset(
            address(peg18),
            address(adapterPeg18),
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
        arm.addBaseAsset(
            address(0),
            address(adapterPeg18),
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
        arm.addBaseAsset(
            address(peg18),
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
        addBaseAsset(peg18); // first registration via shared helper

        vm.prank(governor);
        vm.expectRevert(AbstractARM.AssetAlreadySupported.selector);
        arm.addBaseAsset(
            address(peg18),
            address(adapterPeg18),
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
        arm.addBaseAsset(
            address(badDecimals),
            address(adapterPeg18),
            BUY_PRICE_DEFAULT,
            SELL_PRICE_DEFAULT,
            LIQUIDITY_DEFAULT,
            LIQUIDITY_DEFAULT,
            CROSS_PRICE_DEFAULT,
            true
        );
    }

    function test_AddBaseAsset_RevertWhen_AdapterAssetMismatch() public {
        // An adapter whose asset() (here peg6) is NOT the ARM's liquidityAsset is rejected.
        MockAssetAdapter badAdapter = new MockAssetAdapter(address(arm), address(peg18), address(peg6));
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidAdapterAsset.selector);
        arm.addBaseAsset(
            address(peg18),
            address(badAdapter),
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
        arm.addBaseAsset(
            address(peg18),
            address(adapterPeg18),
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
        arm.addBaseAsset(
            address(peg18),
            address(adapterPeg18),
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
        arm.addBaseAsset(
            address(peg18),
            address(adapterPeg18),
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
        arm.addBaseAsset(
            address(peg18),
            address(adapterPeg18),
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
        arm.addBaseAsset(
            address(peg18),
            address(adapterPeg18),
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
        address[] memory assets = arm.getBaseAssets();
        assertEq(assets.length, 0, "no base assets registered");
    }

    function test_GetBaseAssets_SingleAsset() public {
        addBaseAsset(peg18);

        address[] memory assets = arm.getBaseAssets();
        assertEq(assets.length, 1, "one base asset registered");
        assertEq(assets[0], address(peg18), "first base asset is stETH");
    }

    function test_GetBaseAssets_MultipleAssets_PreservesInsertionOrder() public {
        addBaseAsset(peg18);
        addBaseAsset(adp18);

        // The list mirrors the storage array, so it reflects registration order.
        address[] memory assets = arm.getBaseAssets();
        assertEq(assets.length, 2, "two base assets registered");
        assertEq(assets[0], address(peg18), "first base asset is stETH");
        assertEq(assets[1], address(adp18), "second base asset is wstETH");
    }

    //////////////////////////////////////////////////////
    /// --- setPrices
    //////////////////////////////////////////////////////

    function test_SetPrices_Owner() public {
        addBaseAsset(peg18);

        uint256 newBuy = 0.993e36;
        uint256 newSell = 1.002e36;
        uint256 newBuyLiq = 1_000 ether;
        uint256 newSellLiq = 2_000 ether;

        vm.expectEmit({emitter: address(arm)});
        emit AbstractARM.TraderateChanged(address(peg18), newBuy, newSell, newBuyLiq, newSellLiq);

        vm.prank(governor);
        arm.setPrices(address(peg18), newBuy, newSell, newBuyLiq, newSellLiq);

        assertEq(buyPrice(peg18), newBuy, "buyPrice");
        assertEq(sellPrice(peg18), newSell, "sellPrice");
        assertEq(buyLiquidityRemaining(peg18), newBuyLiq, "buyLiquidityRemaining");
        assertEq(sellLiquidityRemaining(peg18), newSellLiq, "sellLiquidityRemaining");
    }

    function test_SetPrices_Operator() public {
        // Operator is the dual-authority role; assert it can update prices just like the owner.
        addBaseAsset(peg18);

        vm.prank(operator);
        arm.setPrices(address(peg18), 0.994e36, 1.003e36, 1 ether, 2 ether);

        assertEq(buyPrice(peg18), 0.994e36, "buyPrice after operator update");
    }

    function test_SetPrices_RevertWhen_NotAuthorized() public {
        addBaseAsset(peg18);

        vm.prank(alice);
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        arm.setPrices(address(peg18), BUY_PRICE_DEFAULT, SELL_PRICE_DEFAULT, 1 ether, 1 ether);
    }

    function test_SetPrices_RevertWhen_UnsupportedAsset() public {
        // No addBaseAsset → adapter is the zero address.
        vm.prank(governor);
        vm.expectRevert(AbstractARM.UnsupportedAsset.selector);
        arm.setPrices(address(peg18), BUY_PRICE_DEFAULT, SELL_PRICE_DEFAULT, 1 ether, 1 ether);
    }

    function test_SetPrices_RevertWhen_SellBelowCross() public {
        addBaseAsset(peg18);
        vm.prank(governor);
        vm.expectRevert(AbstractARM.SellPriceTooLow.selector);
        arm.setPrices(address(peg18), BUY_PRICE_DEFAULT, CROSS_PRICE_DEFAULT - 1, 1 ether, 1 ether);
    }

    function test_SetPrices_RevertWhen_BuyBelowMinimum() public {
        addBaseAsset(peg18);
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidBuyPrice.selector);
        arm.setPrices(address(peg18), MAX_CROSS_PRICE_DEVIATION - 1, SELL_PRICE_DEFAULT, 1 ether, 1 ether);
    }

    function test_SetPrices_RevertWhen_BuyAtOrAboveCross() public {
        addBaseAsset(peg18);
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidBuyPrice.selector);
        arm.setPrices(address(peg18), CROSS_PRICE_DEFAULT, SELL_PRICE_DEFAULT, 1 ether, 1 ether);
    }

    //////////////////////////////////////////////////////
    /// --- setCrossPrice
    //////////////////////////////////////////////////////

    function test_SetCrossPrice_Lower_WithoutExposure() public {
        addBaseAsset(peg18);
        // No stETH balance, no pendingRedeem → the lowering-only exposure check is skipped.

        uint256 newCross = 0.999e36;
        vm.expectEmit({emitter: address(arm)});
        emit AbstractARM.CrossPriceUpdated(address(peg18), newCross);

        vm.prank(governor);
        arm.setCrossPrice(address(peg18), newCross);

        assertEq(crossPrice(peg18), newCross, "crossPrice lowered");
    }

    function test_SetCrossPrice_Raise() public {
        addBaseAsset(peg18);

        // Lower first so we can raise back up. (At default, cross == PRICE_SCALE which is the ceiling.)
        vm.prank(governor);
        arm.setCrossPrice(address(peg18), 0.999e36);

        vm.prank(governor);
        arm.setCrossPrice(address(peg18), PRICE_SCALE);

        assertEq(crossPrice(peg18), PRICE_SCALE, "crossPrice raised back to PRICE_SCALE");
    }

    function test_SetCrossPrice_RevertWhen_NotOwner() public {
        addBaseAsset(peg18);
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        arm.setCrossPrice(address(peg18), 0.999e36);
    }

    function test_SetCrossPrice_RevertWhen_UnsupportedAsset() public {
        vm.prank(governor);
        vm.expectRevert(AbstractARM.UnsupportedAsset.selector);
        arm.setCrossPrice(address(peg18), CROSS_PRICE_DEFAULT);
    }

    function test_SetCrossPrice_RevertWhen_TooLow() public {
        addBaseAsset(peg18);
        vm.prank(governor);
        vm.expectRevert(AbstractARM.CrossPriceTooLow.selector);
        arm.setCrossPrice(address(peg18), PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION - 1);
    }

    function test_SetCrossPrice_RevertWhen_TooHigh() public {
        addBaseAsset(peg18);
        vm.prank(governor);
        vm.expectRevert(AbstractARM.CrossPriceTooHigh.selector);
        arm.setCrossPrice(address(peg18), PRICE_SCALE + 1);
    }

    function test_SetCrossPrice_RevertWhen_SellBelowNewCross() public {
        addBaseAsset(peg18);

        // Step 1: drop cross down to the floor so we can drop sell below 1e36.
        vm.prank(governor);
        arm.setCrossPrice(address(peg18), PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION);
        // Step 2: bring sell to a value below PRICE_SCALE (within the new cross floor).
        vm.prank(governor);
        arm.setPrices(address(peg18), BUY_PRICE_DEFAULT, PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION, 1 ether, 1 ether);
        // Step 3: raising cross above the new sell triggers the guard.
        vm.prank(governor);
        vm.expectRevert(AbstractARM.SellPriceTooLow.selector);
        arm.setCrossPrice(address(peg18), 0.999e36);
    }

    function test_SetCrossPrice_RevertWhen_BuyAtOrAboveNewCross() public {
        addBaseAsset(peg18);

        // Raise buy close to cross so a tiny lowering of cross collides with it.
        vm.prank(governor);
        arm.setPrices(address(peg18), 0.999e36, SELL_PRICE_DEFAULT, 1 ether, 1 ether);

        // newCross == buyPrice triggers buyPrice >= newCrossPrice.
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidBuyPrice.selector);
        arm.setCrossPrice(address(peg18), 0.999e36);
    }

    function test_SetCrossPrice_RevertWhen_TooManyBaseAssets() public {
        addBaseAsset(peg18);

        // Park enough stETH on the ARM that, valued at the cross price, exposure >= MIN_TOTAL_SUPPLY.
        // MIN_TOTAL_SUPPLY == 1e12; stETH is valued 1:1 at cross == 1e36, so any balance >= 1e12 wei
        // hits the guard. Deal a generous amount so the inequality is unambiguous.
        deal(address(peg18), address(arm), 1 ether);

        vm.prank(governor);
        vm.expectRevert(AbstractARM.TooManyBaseAssets.selector);
        arm.setCrossPrice(address(peg18), 0.999e36);
    }

    //////////////////////////////////////////////////////
    /// --- setFee
    //////////////////////////////////////////////////////

    function test_SetFee_Default() public {
        uint256 newFee = 1_500; // 15%

        vm.expectEmit({emitter: address(arm)});
        emit AbstractARM.FeeUpdated(newFee);

        vm.prank(governor);
        arm.setFee(newFee);

        assertEq(arm.fee(), newFee, "fee updated");
    }

    function test_SetFee_FlushesAccruedFees() public {
        // _setFee calls collectFees() internally — accrued fees must flow to the collector before
        // the rate changes. Trigger the accrual through a real swap (no storage poking).
        uint256 accrued = _accrueFeesViaSwap();
        uint256 collectorBefore = liquidity.balanceOf(feeCollector);

        vm.prank(governor);
        arm.setFee(500);

        assertEq(arm.feesAccrued(), 0, "feesAccrued zeroed");
        assertEq(liquidity.balanceOf(feeCollector) - collectorBefore, accrued, "collector received accrued");
        assertEq(arm.fee(), 500, "fee updated after flush");
    }

    function test_SetFee_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        arm.setFee(100);
    }

    function test_SetFee_RevertWhen_FeeTooHigh() public {
        // Maximum allowed fee is 50% (FEE_SCALE / 2 == 5_000).
        vm.prank(governor);
        vm.expectRevert(AbstractARM.FeeTooHigh.selector);
        arm.setFee(FEE_SCALE / 2 + 1);
    }

    //////////////////////////////////////////////////////
    /// --- setFeeCollector
    //////////////////////////////////////////////////////

    function test_SetFeeCollector_Default() public {
        address newCollector = makeAddr("newCollector");

        vm.expectEmit({emitter: address(arm)});
        emit AbstractARM.FeeCollectorUpdated(newCollector);

        vm.prank(governor);
        arm.setFeeCollector(newCollector);

        assertEq(arm.feeCollector(), newCollector, "feeCollector updated");
    }

    function test_SetFeeCollector_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        arm.setFeeCollector(makeAddr("rejected"));
    }

    function test_SetFeeCollector_RevertWhen_ZeroAddress() public {
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidFeeCollector.selector);
        arm.setFeeCollector(address(0));
    }

    //////////////////////////////////////////////////////
    /// --- collectFees
    //////////////////////////////////////////////////////

    function test_CollectFees_ZeroAccrued_ReturnsZeroNoTransfer() public {
        assertEq(arm.feesAccrued(), 0, "feesAccrued starts at 0");
        uint256 collectorBefore = liquidity.balanceOf(feeCollector);

        uint256 collected = arm.collectFees();

        assertEq(collected, 0, "returns 0 when nothing accrued");
        assertEq(liquidity.balanceOf(feeCollector), collectorBefore, "no transfer when 0 accrued");
    }

    function test_CollectFees_NonZero_TransfersToCollector() public {
        uint256 accrued = _accrueFeesViaSwap();
        uint256 collectorBefore = liquidity.balanceOf(feeCollector);

        vm.expectEmit({emitter: address(arm)});
        emit AbstractARM.FeeCollected(feeCollector, accrued);

        uint256 collected = arm.collectFees();

        assertEq(collected, accrued, "returns accrued amount");
        assertEq(arm.feesAccrued(), 0, "feesAccrued zeroed");
        assertEq(liquidity.balanceOf(feeCollector) - collectorBefore, accrued, "collector received");
    }

    function test_CollectFees_RevertWhen_InsufficientLiquidity() public {
        // Natural setup for the guard: accrue some fees via a real swap, then reserve most of
        // the ARM's WETH for an LP withdrawal so `reservedWithdrawLiquidity + fees` exceeds the
        // on-hand WETH balance.
        _accrueFeesViaSwap();

        // After the swap the ARM holds ~90 ether of WETH; reserving 95 ether of shares pushes
        // reservedWithdrawLiquidity past the balance even before the (small) fee is added.
        vm.prank(alice);
        arm.requestRedeem(95 ether);

        vm.expectRevert(AbstractARM.InsufficientLiquidity.selector);
        arm.collectFees();
    }

    //////////////////////////////////////////////////////
    /// --- setCapManager
    //////////////////////////////////////////////////////

    function test_SetCapManager_ToNonZero() public {
        address newCapManager = makeAddr("newCapManager");

        vm.expectEmit({emitter: address(arm)});
        emit AbstractARM.CapManagerUpdated(newCapManager);

        vm.prank(governor);
        arm.setCapManager(newCapManager);

        assertEq(arm.capManager(), newCapManager, "capManager updated");
    }

    function test_SetCapManager_ToZero_DisablesCaps() public {
        // Documented behavior: passing the zero address disables caps without further checks.
        vm.prank(governor);
        arm.setCapManager(address(0));
        assertEq(arm.capManager(), address(0), "capManager cleared");
    }

    function test_SetCapManager_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        arm.setCapManager(makeAddr("rejected"));
    }

    //////////////////////////////////////////////////////
    /// --- setARMBuffer
    //////////////////////////////////////////////////////

    function test_SetARMBuffer_Owner() public {
        uint256 newBuffer = 0.25e18; // 25%

        vm.expectEmit({emitter: address(arm)});
        emit AbstractARM.ARMBufferUpdated(newBuffer);

        vm.prank(governor);
        arm.setARMBuffer(newBuffer);

        assertEq(arm.armBuffer(), newBuffer, "armBuffer updated by owner");
    }

    function test_SetARMBuffer_Operator() public {
        vm.prank(operator);
        arm.setARMBuffer(0.5e18);
        assertEq(arm.armBuffer(), 0.5e18, "armBuffer updated by operator");
    }

    function test_SetARMBuffer_BoundaryMax() public {
        // 100% is the inclusive upper bound (1e18).
        vm.prank(governor);
        arm.setARMBuffer(1e18);
        assertEq(arm.armBuffer(), 1e18, "armBuffer at boundary 1e18");
    }

    function test_SetARMBuffer_RevertWhen_NotAuthorized() public {
        vm.prank(alice);
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        arm.setARMBuffer(0.1e18);
    }

    function test_SetARMBuffer_RevertWhen_AboveMax() public {
        // 100% + 1 wei reverts; the guard is strictly `> 1e18`.
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidARMBuffer.selector);
        arm.setARMBuffer(1e18 + 1);
    }
}
