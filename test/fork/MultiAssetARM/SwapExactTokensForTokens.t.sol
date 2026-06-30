// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Fork_Shared_Test} from "test/fork/MultiAssetARM/shared/Shared.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

/// @notice Fork tests for `swapExactTokensForTokens` on the MultiAssetARM, both directions, for the
///         four Lido/EtherFi base assets. The expected amounts use the same per-asset conversion the
///         ARM applies (1:1 for pegged stETH/eETH, the live wrapper rate for wstETH/weETH).
contract Fork_Concrete_MultiAssetARM_swapExactTokensForTokens_Test_ is Fork_Shared_Test {
    uint256 public constant AMOUNT_IN = 100 ether;
    /// @dev stETH/eETH are rebasing, so transferred balances can round by 1-2 wei.
    uint256 internal constant REBASE_TOLERANCE = 2;

    //////////////////////////////////////////////////////
    /// --- WETH -> base (sell side: the ARM sells the base asset)
    //////////////////////////////////////////////////////
    function test_swapExactTokensForTokens_WETH_To_stETH() public {
        _swapSell(steth);
    }

    function test_swapExactTokensForTokens_WETH_To_wstETH() public {
        _swapSell(wsteth);
    }

    function test_swapExactTokensForTokens_WETH_To_eETH() public {
        _swapSell(eeth);
    }

    function test_swapExactTokensForTokens_WETH_To_weETH() public {
        _swapSell(weeth);
    }

    //////////////////////////////////////////////////////
    /// --- base -> WETH (buy side: the ARM buys the base asset and accrues a fee)
    //////////////////////////////////////////////////////
    function test_swapExactTokensForTokens_stETH_To_WETH() public {
        _swapBuy(steth);
    }

    function test_swapExactTokensForTokens_wstETH_To_WETH() public {
        _swapBuy(wsteth);
    }

    function test_swapExactTokensForTokens_eETH_To_WETH() public {
        _swapBuy(eeth);
    }

    function test_swapExactTokensForTokens_weETH_To_WETH() public {
        _swapBuy(weeth);
    }

    //////////////////////////////////////////////////////
    /// --- path (Uniswap V2) signature
    //////////////////////////////////////////////////////
    function test_swapExactTokensForTokens_WETH_To_wstETH_PathSig() public {
        uint256 expectedAmountOut = _convertToShares(wsteth, AMOUNT_IN) * PRICE_SCALE / _sellPrice(wsteth);

        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 wstethBefore = wsteth.balanceOf(address(this));

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(wsteth);

        uint256[] memory obtained =
            arm.swapExactTokensForTokens(AMOUNT_IN, 0, path, address(this), block.timestamp + 1 hours);

        assertEq(obtained[0], AMOUNT_IN, "amountIn");
        assertEq(obtained[1], expectedAmountOut, "amountOut");
        assertEq(weth.balanceOf(address(this)), wethBefore - AMOUNT_IN, "WETH spent");
        assertEq(wsteth.balanceOf(address(this)), wstethBefore + expectedAmountOut, "wstETH received");
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_swapExactTokensForTokens_Because_InvalidInToken() public {
        vm.expectRevert(AbstractARM.InvalidSwapAssets.selector);
        arm.swapExactTokensForTokens(badToken, weth, AMOUNT_IN, 0, address(this));
    }

    function test_RevertWhen_swapExactTokensForTokens_Because_InvalidOutToken() public {
        vm.expectRevert(AbstractARM.InvalidSwapAssets.selector);
        arm.swapExactTokensForTokens(weth, badToken, AMOUNT_IN, 0, address(this));

        vm.expectRevert(AbstractARM.InvalidSwapAssets.selector);
        arm.swapExactTokensForTokens(steth, badToken, AMOUNT_IN, 0, address(this));
    }

    function test_RevertWhen_swapExactTokensForTokens_Because_InsufficientOutputAmount() public {
        uint256 highMinAmountOut = 1_000_000 ether;

        vm.expectRevert(AbstractARM.InsufficientOutputAmount.selector);
        arm.swapExactTokensForTokens(steth, weth, AMOUNT_IN, highMinAmountOut, address(this));

        vm.expectRevert(AbstractARM.InsufficientOutputAmount.selector);
        arm.swapExactTokensForTokens(weth, steth, AMOUNT_IN, highMinAmountOut, address(this));
    }

    function test_RevertWhen_swapExactTokensForTokens_Because_DeadlineExpired() public {
        uint256 pastDeadline = block.timestamp - 1;
        address[] memory path = new address[](2);
        path[0] = address(steth);
        path[1] = address(weth);

        vm.expectRevert(AbstractARM.DeadlineExpired.selector);
        arm.swapExactTokensForTokens(AMOUNT_IN, 0, path, address(this), pastDeadline);
    }

    function test_RevertWhen_swapExactTokensForTokens_Because_InvalidePathLength() public {
        address[] memory shortPath = new address[](1);
        shortPath[0] = address(steth);

        vm.expectRevert(AbstractARM.InvalidPathLength.selector);
        arm.swapExactTokensForTokens(AMOUNT_IN, 0, shortPath, address(this), block.timestamp + 1 hours);

        address[] memory longPath = new address[](3);
        longPath[0] = address(steth);
        longPath[1] = address(weth);
        longPath[2] = address(steth);

        vm.expectRevert(AbstractARM.InvalidPathLength.selector);
        arm.swapExactTokensForTokens(AMOUNT_IN, 0, longPath, address(this), block.timestamp + 1 hours);
    }

    function test_RevertWhen_swapExactTokensForTokens_Because_InsufficientLiquidity() public {
        // Reserve all WETH liquidity behind an LP redeem request, leaving none for a buy-side payout.
        arm.requestRedeem(arm.balanceOf(address(this)));

        vm.expectRevert(AbstractARM.InsufficientLiquidity.selector);
        arm.swapExactTokensForTokens(steth, weth, AMOUNT_IN, 0, address(this));
    }

    //////////////////////////////////////////////////////
    /// --- SHARED SWAP LOGIC
    //////////////////////////////////////////////////////
    /// @dev WETH in, base asset out. The ARM prices the sale at sellPrice.
    function _swapSell(IERC20 token) internal {
        uint256 expectedAmountOut = _convertToShares(token, AMOUNT_IN) * PRICE_SCALE / _sellPrice(token);

        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 baseBefore = token.balanceOf(address(this));

        uint256[] memory obtained = arm.swapExactTokensForTokens(weth, token, AMOUNT_IN, 0, address(this));

        assertEq(obtained[0], AMOUNT_IN, "amountIn");
        assertEq(obtained[1], expectedAmountOut, "amountOut");
        assertEq(weth.balanceOf(address(this)), wethBefore - AMOUNT_IN, "WETH spent");
        assertApproxEqAbs(
            token.balanceOf(address(this)), baseBefore + expectedAmountOut, REBASE_TOLERANCE, "base received"
        );
    }

    /// @dev base asset in, WETH out. The ARM prices the purchase at buyPrice and accrues a fee.
    function _swapBuy(IERC20 token) internal {
        uint256 buyPrice = _buyPrice(token);
        uint256 expectedAmountOut = _convertToAssets(token, AMOUNT_IN) * buyPrice / PRICE_SCALE;
        uint256 expectedFee =
            expectedAmountOut * _swapFeeMultiplier(buyPrice, _crossPrice(token), arm.fee()) / PRICE_SCALE;

        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 baseBefore = token.balanceOf(address(this));
        uint256 feesBefore = arm.feesAccrued();

        uint256[] memory obtained = arm.swapExactTokensForTokens(token, weth, AMOUNT_IN, 0, address(this));

        assertEq(obtained[0], AMOUNT_IN, "amountIn");
        assertEq(obtained[1], expectedAmountOut, "amountOut");
        assertEq(weth.balanceOf(address(this)), wethBefore + expectedAmountOut, "WETH received");
        assertApproxEqAbs(token.balanceOf(address(this)), baseBefore - AMOUNT_IN, REBASE_TOLERANCE, "base spent");
        assertEq(arm.feesAccrued() - feesBefore, expectedFee, "fee accrued");
    }
}
