// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Fork_Shared_Test} from "test/fork/PaxosARM/shared/Shared.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

/// @notice Fork tests for `swapTokensForExactTokens` on the Paxos MultiAssetARM. The required
///         input mirrors the ARM solver, including the +3 wei rounding buffer it adds on
///         exact-output swaps. Both base assets are pegged 1:1 to USDC with equal (6) decimals.
contract Fork_Concrete_PaxosARM_swapTokensForExactTokens_Test_ is Fork_Shared_Test {
    uint256 public constant AMOUNT_OUT = 10_000e6;

    //////////////////////////////////////////////////////
    /// --- base -> USDC (buy side: the ARM buys the base asset and accrues a fee)
    //////////////////////////////////////////////////////
    function test_swapTokensForExactTokens_Pyusd_To_Usdc() public {
        uint256 buyPrice = _buyPrice(pyusd);
        uint256 expectedAmountIn = AMOUNT_OUT * PRICE_SCALE / buyPrice + 3;
        uint256 expectedFee = _expectedBuySideFee(pyusd, expectedAmountIn, AMOUNT_OUT);

        uint256 usdcBefore = usdc.balanceOf(address(this));
        uint256 baseBefore = pyusd.balanceOf(address(this));
        uint256 feesBefore = arm.feesAccrued();

        uint256[] memory obtained =
            arm.swapTokensForExactTokens(pyusd, usdc, AMOUNT_OUT, type(uint256).max, address(this));

        assertEq(obtained[0], expectedAmountIn, "amountIn");
        assertEq(obtained[1], AMOUNT_OUT, "amountOut");
        assertEq(usdc.balanceOf(address(this)), usdcBefore + AMOUNT_OUT, "USDC received");
        assertEq(pyusd.balanceOf(address(this)), baseBefore - expectedAmountIn, "PYUSD spent");
        assertEq(arm.feesAccrued() - feesBefore, expectedFee, "fee accrued");
    }

    //////////////////////////////////////////////////////
    /// --- USDC -> base (sell side: the ARM sells the base asset)
    //////////////////////////////////////////////////////
    function test_swapTokensForExactTokens_Usdc_To_Usdg() public {
        uint256 expectedAmountIn = AMOUNT_OUT * _sellPrice(usdg) / PRICE_SCALE + 3;

        uint256 usdcBefore = usdc.balanceOf(address(this));
        uint256 baseBefore = usdg.balanceOf(address(this));

        uint256[] memory obtained =
            arm.swapTokensForExactTokens(usdc, usdg, AMOUNT_OUT, type(uint256).max, address(this));

        assertEq(expectedAmountIn, AMOUNT_OUT + 3, "sell price 1e36 means in == out + 3 wei buffer");
        assertEq(obtained[0], expectedAmountIn, "amountIn");
        assertEq(obtained[1], AMOUNT_OUT, "amountOut");
        assertEq(usdc.balanceOf(address(this)), usdcBefore - expectedAmountIn, "USDC spent");
        assertEq(usdg.balanceOf(address(this)), baseBefore + AMOUNT_OUT, "USDG received");
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_swapTokensForExactTokens_Because_ExcessInputAmount() public {
        uint256 lowMaxAmountIn = 100e6;

        vm.expectRevert(AbstractARM.ExcessInputAmount.selector);
        arm.swapTokensForExactTokens(pyusd, usdc, AMOUNT_OUT, lowMaxAmountIn, address(this));

        vm.expectRevert(AbstractARM.ExcessInputAmount.selector);
        arm.swapTokensForExactTokens(usdc, usdg, AMOUNT_OUT, lowMaxAmountIn, address(this));
    }
}
