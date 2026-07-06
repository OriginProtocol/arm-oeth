// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Fork_Shared_Test} from "test/fork/MultiAssetARM/shared/Shared.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

/// @notice Fork tests for `swapTokensForExactTokens` on the MultiAssetARM, both directions, for the
///         four Lido/EtherFi base assets. The required input mirrors the ARM solver, including the
///         +3 wei rounding buffer it adds on exact-output swaps.
contract Fork_Concrete_MultiAssetARM_swapTokensForExactTokens_Test_ is Fork_Shared_Test {
    uint256 public constant AMOUNT_OUT = 100 ether;
    /// @dev stETH/eETH are rebasing, so transferred balances can round by 1-2 wei.
    uint256 internal constant REBASE_TOLERANCE = 2;

    //////////////////////////////////////////////////////
    /// --- WETH -> base (sell side: the ARM sells the base asset)
    //////////////////////////////////////////////////////
    function test_swapTokensForExactTokens_WETH_To_stETH() public {
        _swapSellExact(steth);
    }

    function test_swapTokensForExactTokens_WETH_To_wstETH() public {
        _swapSellExact(wsteth);
    }

    function test_swapTokensForExactTokens_WETH_To_eETH() public {
        _swapSellExact(eeth);
    }

    function test_swapTokensForExactTokens_WETH_To_weETH() public {
        _swapSellExact(weeth);
    }

    //////////////////////////////////////////////////////
    /// --- base -> WETH (buy side: the ARM buys the base asset and accrues a fee)
    //////////////////////////////////////////////////////
    function test_swapTokensForExactTokens_stETH_To_WETH() public {
        _swapBuyExact(steth);
    }

    function test_swapTokensForExactTokens_wstETH_To_WETH() public {
        _swapBuyExact(wsteth);
    }

    function test_swapTokensForExactTokens_eETH_To_WETH() public {
        _swapBuyExact(eeth);
    }

    function test_swapTokensForExactTokens_weETH_To_WETH() public {
        _swapBuyExact(weeth);
    }

    //////////////////////////////////////////////////////
    /// --- path (Uniswap V2) signature
    //////////////////////////////////////////////////////
    function test_swapTokensForExactTokens_WETH_To_wstETH_PathSig() public {
        uint256 expectedAmountIn = _convertToAssets(wsteth, AMOUNT_OUT) * _sellPrice(wsteth) / PRICE_SCALE + 3;

        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 wstethBefore = wsteth.balanceOf(address(this));

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(wsteth);

        uint256[] memory obtained =
            arm.swapTokensForExactTokens(AMOUNT_OUT, type(uint256).max, path, address(this), block.timestamp + 1 hours);

        assertEq(obtained[0], expectedAmountIn, "amountIn");
        assertEq(obtained[1], AMOUNT_OUT, "amountOut");
        assertEq(weth.balanceOf(address(this)), wethBefore - expectedAmountIn, "WETH spent");
        assertEq(wsteth.balanceOf(address(this)), wstethBefore + AMOUNT_OUT, "wstETH received");
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_swapTokensForExactTokens_Because_InvalidInToken() public {
        vm.expectRevert(AbstractARM.InvalidSwapAssets.selector);
        arm.swapTokensForExactTokens(badToken, weth, AMOUNT_OUT, 0, address(this));
    }

    function test_RevertWhen_swapTokensForExactTokens_Because_InvalidOutToken() public {
        vm.expectRevert(AbstractARM.InvalidSwapAssets.selector);
        arm.swapTokensForExactTokens(weth, badToken, AMOUNT_OUT, 0, address(this));

        vm.expectRevert(AbstractARM.InvalidSwapAssets.selector);
        arm.swapTokensForExactTokens(steth, badToken, AMOUNT_OUT, 0, address(this));
    }

    function test_RevertWhen_swapTokensForExactTokens_Because_ExcessInputAmount() public {
        uint256 lowMaxAmountIn = 10 ether;

        vm.expectRevert(AbstractARM.ExcessInputAmount.selector);
        arm.swapTokensForExactTokens(steth, weth, AMOUNT_OUT, lowMaxAmountIn, address(this));

        vm.expectRevert(AbstractARM.ExcessInputAmount.selector);
        arm.swapTokensForExactTokens(weth, steth, AMOUNT_OUT, lowMaxAmountIn, address(this));
    }

    function test_RevertWhen_swapTokensForExactTokens_Because_DeadlineExpired() public {
        uint256 pastDeadline = block.timestamp - 1;
        address[] memory path = new address[](2);
        path[0] = address(steth);
        path[1] = address(weth);

        vm.expectRevert(AbstractARM.DeadlineExpired.selector);
        arm.swapTokensForExactTokens(AMOUNT_OUT, type(uint256).max, path, address(this), pastDeadline);
    }

    function test_RevertWhen_swapTokensForExactTokens_Because_InvalidePathLength() public {
        address[] memory shortPath = new address[](1);
        shortPath[0] = address(steth);

        vm.expectRevert(AbstractARM.InvalidPathLength.selector);
        arm.swapTokensForExactTokens(AMOUNT_OUT, 0, shortPath, address(this), block.timestamp + 1 hours);

        address[] memory longPath = new address[](3);
        longPath[0] = address(steth);
        longPath[1] = address(weth);
        longPath[2] = address(steth);

        vm.expectRevert(AbstractARM.InvalidPathLength.selector);
        arm.swapTokensForExactTokens(AMOUNT_OUT, 0, longPath, address(this), block.timestamp + 1 hours);
    }

    //////////////////////////////////////////////////////
    /// --- SHARED SWAP LOGIC
    //////////////////////////////////////////////////////
    /// @dev WETH in, exact base asset out. The ARM prices the sale at sellPrice (+3 wei buffer).
    function _swapSellExact(IERC20 token) internal {
        uint256 expectedAmountIn = _convertToAssets(token, AMOUNT_OUT) * _sellPrice(token) / PRICE_SCALE + 3;

        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 baseBefore = token.balanceOf(address(this));

        uint256[] memory obtained =
            arm.swapTokensForExactTokens(weth, token, AMOUNT_OUT, type(uint256).max, address(this));

        assertEq(obtained[0], expectedAmountIn, "amountIn");
        assertEq(obtained[1], AMOUNT_OUT, "amountOut");
        assertEq(weth.balanceOf(address(this)), wethBefore - expectedAmountIn, "WETH spent");
        assertApproxEqAbs(token.balanceOf(address(this)), baseBefore + AMOUNT_OUT, REBASE_TOLERANCE, "base received");
    }

    /// @dev base asset in, exact WETH out. The ARM prices the purchase at buyPrice (+3 wei buffer) and accrues a fee.
    function _swapBuyExact(IERC20 token) internal {
        uint256 buyPrice = _buyPrice(token);
        uint256 expectedAmountIn = _convertToShares(token, AMOUNT_OUT) * PRICE_SCALE / buyPrice + 3;
        uint256 expectedFee = AMOUNT_OUT * _swapFeeMultiplier(buyPrice, _crossPrice(token), arm.fee()) / PRICE_SCALE;

        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 baseBefore = token.balanceOf(address(this));
        uint256 feesBefore = arm.feesAccrued();

        uint256[] memory obtained =
            arm.swapTokensForExactTokens(token, weth, AMOUNT_OUT, type(uint256).max, address(this));

        assertEq(obtained[0], expectedAmountIn, "amountIn");
        assertEq(obtained[1], AMOUNT_OUT, "amountOut");
        assertEq(weth.balanceOf(address(this)), wethBefore + AMOUNT_OUT, "WETH received");
        assertApproxEqAbs(token.balanceOf(address(this)), baseBefore - expectedAmountIn, REBASE_TOLERANCE, "base spent");
        assertEq(arm.feesAccrued() - feesBefore, expectedFee, "fee accrued");
    }
}
