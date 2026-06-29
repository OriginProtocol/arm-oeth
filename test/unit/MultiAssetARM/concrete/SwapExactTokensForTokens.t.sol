// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_MultiAssetARM_Shared_Test} from "../Shared.t.sol";
import {IERC20} from "contracts/Interfaces.sol";

/// @notice Exact-input swaps, run at both 18 and 6 decimal liquidity, across the 6/18 x pegged/adapter base
///         matrix. Expected outputs are derived from the harness scaling helpers, so the same assertions hold
///         at any decimal combination. SELL legs (liquidity -> base) carry no price factor (sell == cross);
///         BUY legs (base -> liquidity) apply the 0.998 buy discount.
abstract contract SwapExactTokensForTokens_Test is Unit_MultiAssetARM_Shared_Test {
    function setUp() public virtual override {
        super.setUp();
        desactiveCapManager();
    }

    function _sellLiquidityForBase(IERC20 base) internal {
        uint256 amountIn = DEFAULT_AMOUNT(); // 100 liquidity tokens
        dealBaseToARM(base, 1e30);
        _mint(liquidity, alice, amountIn);

        vm.prank(alice);
        uint256[] memory amounts = arm.swapExactTokensForTokens(liquidity, base, amountIn, 0, alice);

        uint256 expected = _scaleLiquidityToBase(base, amountIn);
        assertEq(amounts[1], expected, "sell: scaled base out");
        assertEq(base.balanceOf(alice), expected, "alice base out");
    }

    function _buyLiquidityWithBase(IERC20 base) internal {
        uint256 amountIn = 100 * (10 ** base.decimals()); // 100 base tokens
        dealLiquidityToARM(1_000_000 * LIQUIDITY_UNIT());
        dealBaseToUser(base, alice, amountIn);

        vm.prank(alice);
        uint256[] memory amounts = arm.swapExactTokensForTokens(base, liquidity, amountIn, 0, alice);

        uint256 expected = _scaleBaseToLiquidity(base, amountIn) * BUY_PRICE / PRICE_SCALE;
        assertEq(amounts[1], expected, "buy: scaled liquidity out at buy price");
    }

    // --- SELL: liquidity -> base
    function test_Sell_Peg6() public {
        _sellLiquidityForBase(peg6);
    }

    function test_Sell_Peg18() public {
        _sellLiquidityForBase(peg18);
    }

    function test_Sell_Adp6() public {
        _sellLiquidityForBase(adp6);
    }

    function test_Sell_Adp18() public {
        _sellLiquidityForBase(adp18);
    }

    // --- BUY: base -> liquidity
    function test_Buy_Peg6() public {
        _buyLiquidityWithBase(peg6);
    }

    function test_Buy_Peg18() public {
        _buyLiquidityWithBase(peg18);
    }

    function test_Buy_Adp6() public {
        _buyLiquidityWithBase(adp6);
    }

    function test_Buy_Adp18() public {
        _buyLiquidityWithBase(adp18);
    }

    /// @dev A yield-bearing adapter (rate > 1) raises the per-unit value before the buy discount.
    function test_Buy_Adp18_NonUnitRate() public {
        adapterAdp18.setRate(1.05e18);
        uint256 amountIn = 100 * 1e18;
        dealLiquidityToARM(1_000_000 * LIQUIDITY_UNIT());
        dealBaseToUser(adp18, alice, amountIn);

        vm.prank(alice);
        uint256[] memory amounts = arm.swapExactTokensForTokens(adp18, liquidity, amountIn, 0, alice);

        uint256 conv = _scaleBaseToLiquidity(adp18, amountIn) * 1.05e18 / 1e18;
        assertEq(amounts[1], conv * BUY_PRICE / PRICE_SCALE, "rate-scaled adapter buy");
    }
}

contract SwapExactTokensForTokens_18dec_Test is SwapExactTokensForTokens_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 18;
    }
}

contract SwapExactTokensForTokens_6dec_Test is SwapExactTokensForTokens_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 6;
    }
}
