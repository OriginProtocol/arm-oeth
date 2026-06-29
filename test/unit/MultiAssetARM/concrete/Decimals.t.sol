// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_MultiAssetARM_Shared_Test} from "../Shared.t.sol";

/// @notice Dedicated decimal edge-case coverage, run at both 18 and 6 decimal liquidity. Exercises the
///         MIN_LIQUIDITY floor (1e12 vs 1), the always-18-decimal LP shares, and the 1e12 scaling in both
///         directions: scale-up (base 6-dec into 18-dec liquidity, lossless) and scale-down (base 18-dec into
///         6-dec liquidity, sub-unit dust truncated and kept by the vault).
abstract contract Decimals_Test is Unit_MultiAssetARM_Shared_Test {
    function setUp() public virtual override {
        super.setUp();
        desactiveCapManager();
    }

    /// @dev The totalAssets floor equals MIN_LIQUIDITY: 1e12 for an 18-decimal asset, 1 wei for a 6-decimal one.
    function test_TotalAssets_FloorIsMinLiquidity() public view {
        assertEq(arm.totalAssets(), MIN_LIQUIDITY(), "floor == MIN_LIQUIDITY");
        if (liquidityDecimals() == 18) {
            assertEq(MIN_LIQUIDITY(), 1e12, "18-dec floor");
        } else {
            assertEq(MIN_LIQUIDITY(), 1, "6-dec floor");
        }
    }

    /// @dev 1 liquidity token mints exactly 1 LP token (1e18): the share scaling absorbs the decimal gap.
    function test_ShareScaling_OneTokenIsOneLpToken() public {
        uint256 shares = firstDeposit(alice, LIQUIDITY_UNIT());
        assertEq(shares, 1e18, "1 liquidity token -> 1 LP token");
    }

    /// @dev Sub-1e12 balance of an 18-decimal base: truncated to 0 at 6-dec liquidity, kept whole at 18-dec.
    function test_Pegged18_SubUnitDust() public {
        firstDeposit(alice, DEFAULT_AMOUNT());
        uint256 before = arm.totalAssets();

        dealBaseToARM(peg18, 5e11); // < 1e12
        uint256 expected = _scaleBaseToLiquidity(peg18, 5e11);
        assertEq(arm.totalAssets(), before + expected, "dust valued by scaling");

        if (liquidityDecimals() == 6) {
            assertEq(expected, 0, "18-dec base sub-unit dust truncates to 0 in 6-dec liquidity");
        } else {
            assertEq(expected, 5e11, "no truncation when liquidity is 18-dec");
        }
    }

    /// @dev 1 wei of an 18-decimal base rounds to 0 at 6-dec liquidity (scale-down), 1 wei at 18-dec (identity).
    function test_Pegged18_OneWei() public {
        firstDeposit(alice, DEFAULT_AMOUNT());
        uint256 before = arm.totalAssets();
        dealBaseToARM(peg18, 1);
        assertEq(arm.totalAssets(), before + (liquidityDecimals() == 6 ? 0 : 1), "1 wei 18-dec base");
    }

    /// @dev Scale-up (6-dec base into liquidity) is lossless: exactly x1e12 at 18-dec, identity at 6-dec.
    function test_Pegged6_ScaleUpLossless() public {
        firstDeposit(alice, DEFAULT_AMOUNT());
        uint256 before = arm.totalAssets();
        dealBaseToARM(peg6, 50e6);
        uint256 expected = liquidityDecimals() == 18 ? 50e6 * SCALE_1E12 : 50e6;
        assertEq(_scaleBaseToLiquidity(peg6, 50e6), expected, "scale-up exact");
        assertEq(arm.totalAssets(), before + expected, "scale-up adds full value");
    }

    /// @dev On a buy swap with an 18-decimal base, sub-unit dust is truncated (no extra payout) and kept by the
    ///      vault. At 6-dec liquidity, selling 100e18 + dust pays the same as selling a clean 100e18.
    function test_BuySwap_SubUnitBaseDust_KeptByVault() public {
        uint256 amountIn = 100e18 + 5e11;
        dealLiquidityToARM(1_000_000 * LIQUIDITY_UNIT());
        dealBaseToUser(peg18, alice, amountIn);

        vm.prank(alice);
        uint256[] memory amounts = arm.swapExactTokensForTokens(peg18, liquidity, amountIn, 0, alice);

        uint256 expected = _scaleBaseToLiquidity(peg18, amountIn) * BUY_PRICE / PRICE_SCALE;
        assertEq(amounts[1], expected, "output matches scaled-down value at buy price");
        assertEq(peg18.balanceOf(address(arm)), amountIn, "vault keeps the full input incl. dust");

        if (liquidityDecimals() == 6) {
            // 100e18 and 100e18 + 5e11 both scale to 100e6, so the dust earns nothing.
            uint256 clean = _scaleBaseToLiquidity(peg18, 100e18) * BUY_PRICE / PRICE_SCALE;
            assertEq(amounts[1], clean, "dust does not increase the payout at 6-dec liquidity");
        }
    }
}

contract Decimals_18dec_Test is Decimals_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 18;
    }
}

contract Decimals_6dec_Test is Decimals_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 6;
    }
}
