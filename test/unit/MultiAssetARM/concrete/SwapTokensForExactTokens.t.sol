// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_MultiAssetARM_Shared_Test} from "../Shared.t.sol";
import {IERC20} from "contracts/Interfaces.sol";

/// @notice Exact-output swaps, run at both 18 and 6 decimal liquidity. Exercises the `+3` wei rounding buffer
///         (AbstractARM lines 458/466), applied in the INPUT token's native decimals — non-trivial for small
///         6-decimal swaps. SELL legs reduce to `scaledAssets + 3` (sell == cross), isolating the buffer and
///         the decimal scaling; BUY legs apply `/buyPrice + 3`.
abstract contract SwapTokensForExactTokens_Test is Unit_MultiAssetARM_Shared_Test {
    function setUp() public virtual override {
        super.setUp();
        desactiveCapManager();
    }

    // SELL exact-out: buy exact `base`, pay liquidity (+3 buffer in liquidity decimals).
    function _sellExactOut(IERC20 base, uint256 amountOut) internal {
        dealBaseToARM(base, 1e30);
        _mint(liquidity, alice, 1_000_000 * LIQUIDITY_UNIT());

        vm.prank(alice);
        uint256[] memory amounts = arm.swapTokensForExactTokens(liquidity, base, amountOut, type(uint256).max, alice);

        assertEq(amounts[0], _scaleBaseToLiquidity(base, amountOut) + 3, "liquidity in = scaled + 3");
        assertEq(base.balanceOf(alice), amountOut, "exact base out");
    }

    // BUY exact-out: buy exact liquidity, pay `base` (+3 buffer in base decimals).
    function _buyExactOut(IERC20 base) internal {
        uint256 amountOut = DEFAULT_AMOUNT(); // 100 liquidity tokens
        dealLiquidityToARM(1_000_000 * LIQUIDITY_UNIT());
        dealBaseToUser(base, alice, 1e30);

        vm.prank(alice);
        uint256[] memory amounts = arm.swapTokensForExactTokens(base, liquidity, amountOut, type(uint256).max, alice);

        uint256 expected = _scaleLiquidityToBase(base, amountOut) * PRICE_SCALE / BUY_PRICE + 3;
        assertEq(amounts[0], expected, "base in = scaled / buyPrice + 3");
        assertEq(liquidity.balanceOf(alice), amountOut, "exact liquidity out");
    }

    // --- SELL exact-out
    function test_SellExactOut_Peg6() public {
        _sellExactOut(peg6, 100 * 1e6);
    }

    function test_SellExactOut_Peg18() public {
        _sellExactOut(peg18, 100 * 1e18);
    }

    function test_SellExactOut_Adp6() public {
        _sellExactOut(adp6, 100 * 1e6);
    }

    function test_SellExactOut_Adp18() public {
        _sellExactOut(adp18, 100 * 1e18);
    }

    /// @dev On a tiny exact-out the +3 wei buffer is a meaningful fraction of the input (most so at 6 decimals).
    function test_SellExactOut_TinyAmount_BufferApplies() public {
        _sellExactOut(peg6, 10);
    }

    // --- BUY exact-out
    function test_BuyExactOut_Peg6() public {
        _buyExactOut(peg6);
    }

    function test_BuyExactOut_Peg18() public {
        _buyExactOut(peg18);
    }

    function test_BuyExactOut_Adp6() public {
        _buyExactOut(adp6);
    }

    function test_BuyExactOut_Adp18() public {
        _buyExactOut(adp18);
    }
}

contract SwapTokensForExactTokens_18dec_Test is SwapTokensForExactTokens_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function test_BuyExactOut_Peg6_SubBaseUnit_AccruesFeeOnRealizedGain() public {
        uint256 deepBuyPrice = MAX_CROSS_PRICE_DEVIATION; // 0.002e36 = 0.2% of the cross price.
        vm.prank(governor);
        arm.setPrices(address(peg6), deepBuyPrice, SELL_PRICE, type(uint128).max, type(uint128).max);

        uint256 amountOut = 1e12 - 1; // Just below one 6-decimal base unit after scaling by 1e12.
        dealLiquidityToARM(1 ether);
        dealBaseToUser(peg6, alice, 1e6);

        vm.prank(alice);
        uint256[] memory amounts = arm.swapTokensForExactTokens(peg6, liquidity, amountOut, type(uint256).max, alice);

        uint256 realizedAssets = _scaleBaseToLiquidity(peg6, amounts[0]) * CROSS_PRICE / PRICE_SCALE;
        uint256 expectedGain = realizedAssets - amountOut;
        uint256 expectedFee = expectedGain * DEFAULT_FEE / FEE_SCALE;

        assertEq(amounts[0], 3, "input is only the rounding buffer");
        assertEq(arm.feesAccrued(), expectedFee, "fee uses the realized gain");
    }
}

contract SwapTokensForExactTokens_6dec_Test is SwapTokensForExactTokens_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 6;
    }
}
