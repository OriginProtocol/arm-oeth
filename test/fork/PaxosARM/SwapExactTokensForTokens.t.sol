// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Fork_Shared_Test} from "test/fork/PaxosARM/shared/Shared.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

/// @notice Fork tests for `swapExactTokensForTokens` on the Paxos MultiAssetARM, both directions,
///         for the two Paxos base stablecoins. Both assets are pegged 1:1 to USDC with equal (6)
///         decimals, so conversions are the identity and only the buy/sell prices apply.
contract Fork_Concrete_PaxosARM_swapExactTokensForTokens_Test_ is Fork_Shared_Test {
    uint256 public constant AMOUNT_IN = 10_000e6;

    //////////////////////////////////////////////////////
    /// --- base -> USDC (buy side: the ARM buys the base asset and accrues a fee)
    //////////////////////////////////////////////////////
    function test_swapExactTokensForTokens_Pyusd_To_Usdc() public {
        _swapBuy(pyusd);
    }

    function test_swapExactTokensForTokens_Usdg_To_Usdc() public {
        _swapBuy(usdg);
    }

    //////////////////////////////////////////////////////
    /// --- USDC -> base (sell side: the ARM sells the base asset)
    //////////////////////////////////////////////////////
    function test_swapExactTokensForTokens_Usdc_To_Pyusd() public {
        _swapSell(pyusd);
    }

    function test_swapExactTokensForTokens_Usdc_To_Usdg() public {
        _swapSell(usdg);
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_swapExactTokensForTokens_Because_UnsupportedAsset() public {
        vm.expectRevert(AbstractARM.InvalidSwapAssets.selector);
        arm.swapExactTokensForTokens(badToken, usdc, AMOUNT_IN, 0, address(this));

        vm.expectRevert(AbstractARM.InvalidSwapAssets.selector);
        arm.swapExactTokensForTokens(usdc, badToken, AMOUNT_IN, 0, address(this));

        vm.expectRevert(AbstractARM.InvalidSwapAssets.selector);
        arm.swapExactTokensForTokens(pyusd, badToken, AMOUNT_IN, 0, address(this));
    }

    function test_RevertWhen_swapExactTokensForTokens_Because_InsufficientOutputAmount() public {
        uint256 highMinAmountOut = 1_000_000e6;

        vm.expectRevert(AbstractARM.InsufficientOutputAmount.selector);
        arm.swapExactTokensForTokens(pyusd, usdc, AMOUNT_IN, highMinAmountOut, address(this));

        vm.expectRevert(AbstractARM.InsufficientOutputAmount.selector);
        arm.swapExactTokensForTokens(usdc, usdg, AMOUNT_IN, highMinAmountOut, address(this));
    }

    //////////////////////////////////////////////////////
    /// --- SHARED SWAP LOGIC
    //////////////////////////////////////////////////////
    /// @dev base asset in, USDC out. The ARM prices the purchase at buyPrice (0.998) and accrues a fee.
    function _swapBuy(IERC20 token) internal {
        uint256 buyPrice = _buyPrice(token);
        uint256 expectedAmountOut = AMOUNT_IN * buyPrice / PRICE_SCALE;
        uint256 expectedFee = _expectedBuySideFee(token, AMOUNT_IN, expectedAmountOut);

        uint256 usdcBefore = usdc.balanceOf(address(this));
        uint256 baseBefore = token.balanceOf(address(this));
        uint256 feesBefore = arm.feesAccrued();

        uint256[] memory obtained = arm.swapExactTokensForTokens(token, usdc, AMOUNT_IN, 0, address(this));

        assertEq(obtained[0], AMOUNT_IN, "amountIn");
        assertEq(obtained[1], expectedAmountOut, "amountOut");
        assertEq(usdc.balanceOf(address(this)), usdcBefore + expectedAmountOut, "USDC received");
        assertEq(token.balanceOf(address(this)), baseBefore - AMOUNT_IN, "base spent");
        assertEq(arm.feesAccrued() - feesBefore, expectedFee, "fee accrued");
    }

    /// @dev USDC in, base asset out. The ARM prices the sale at sellPrice (1.0), so out equals in.
    function _swapSell(IERC20 token) internal {
        uint256 expectedAmountOut = AMOUNT_IN * PRICE_SCALE / _sellPrice(token);

        uint256 usdcBefore = usdc.balanceOf(address(this));
        uint256 baseBefore = token.balanceOf(address(this));

        uint256[] memory obtained = arm.swapExactTokensForTokens(usdc, token, AMOUNT_IN, 0, address(this));

        assertEq(expectedAmountOut, AMOUNT_IN, "sell price 1e36 means out == in");
        assertEq(obtained[0], AMOUNT_IN, "amountIn");
        assertEq(obtained[1], expectedAmountOut, "amountOut");
        assertEq(usdc.balanceOf(address(this)), usdcBefore - AMOUNT_IN, "USDC spent");
        assertEq(token.balanceOf(address(this)), baseBefore + expectedAmountOut, "base received");
    }
}
