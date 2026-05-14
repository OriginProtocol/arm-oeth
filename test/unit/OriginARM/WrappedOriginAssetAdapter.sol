// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {IERC20} from "contracts/Interfaces.sol";

contract Unit_Concrete_OriginARM_WrappedOriginAssetAdapter_Test_ is Unit_Shared_Test {
    function test_WrappedOriginAssetAdapter_Conversion_UsesWrappedOTokenRate() public {
        uint256 shares = _mintWOETH(address(originARM), 10 ether);
        deal(address(oeth), address(woeth), oeth.balanceOf(address(woeth)) + 1 ether);

        uint256 expectedAssets = woeth.convertToAssets(shares);
        uint256 expectedShares = woeth.convertToShares(expectedAssets);

        assertGt(expectedAssets, shares, "expected appreciating wrapper");
        assertEq(wrappedOriginAssetAdapter.convertToAssets(shares), expectedAssets, "assets");
        assertEq(wrappedOriginAssetAdapter.convertToShares(expectedAssets), expectedShares, "shares");
    }

    function test_SwapExactTokensForTokens_WOETH_For_WETH_UsesWrappedConversion() public {
        uint256 sharesIn = _mintWOETH(alice, 10 ether);
        deal(address(oeth), address(woeth), oeth.balanceOf(address(woeth)) + 1 ether);
        deal(address(weth), address(originARM), 20 ether);

        uint256 convertedAmountIn = woeth.convertToAssets(sharesIn);
        uint256 expectedAmountOut = convertedAmountIn * _woethBuyPrice() / originARM.PRICE_SCALE();

        vm.startPrank(alice);
        woeth.approve(address(originARM), sharesIn);
        uint256[] memory amounts = originARM.swapExactTokensForTokens(IERC20(address(woeth)), weth, sharesIn, 0, alice);
        vm.stopPrank();

        assertEq(amounts[0], sharesIn, "amount in");
        assertEq(amounts[1], expectedAmountOut, "amount out");
        assertEq(weth.balanceOf(alice), expectedAmountOut, "weth received");
    }

    function test_RequestAndClaimRedeem_WOETH() public {
        uint256 shares = _mintWOETH(address(originARM), 10 ether);
        deal(address(oeth), address(woeth), oeth.balanceOf(address(woeth)) + 1 ether);
        uint256 assetsExpected = woeth.convertToAssets(shares);

        vm.prank(governor);
        (uint256 sharesRequested, uint256 requestAssetsExpected) =
            originARM.requestBaseAssetRedeem(address(woeth), shares);

        assertEq(sharesRequested, shares, "shares requested");
        assertEq(requestAssetsExpected, assetsExpected, "assets expected");
        (,,,,, uint120 pendingRedeemAssets,,) = originARM.baseAssetConfigs(address(woeth));
        assertEq(pendingRedeemAssets, assetsExpected, "pending redeem assets");
        assertEq(wrappedOriginAssetAdapter.pendingRequestIdsLength(), 1, "pending request length");

        deal(address(weth), address(vault), assetsExpected);

        vm.prank(governor);
        (uint256 sharesClaimed, uint256 claimAssetsExpected, uint256 assetsReceived) =
            originARM.claimBaseAssetRedeem(address(woeth), shares);

        assertEq(sharesClaimed, shares, "shares claimed");
        assertEq(claimAssetsExpected, assetsExpected, "claim assets expected");
        assertEq(assetsReceived, assetsExpected, "assets received");
        assertEq(weth.balanceOf(address(originARM)), MIN_TOTAL_SUPPLY + assetsExpected, "arm weth");

        (,,,,, pendingRedeemAssets,,) = originARM.baseAssetConfigs(address(woeth));
        assertEq(pendingRedeemAssets, 0, "pending redeem assets after claim");
    }

    function _mintWOETH(address to, uint256 assets) internal returns (uint256 shares) {
        deal(address(oeth), address(this), assets);
        oeth.approve(address(woeth), assets);
        shares = woeth.deposit(assets, to);
    }

    function _woethBuyPrice() internal view returns (uint256 buyPrice) {
        (uint128 buyPriceMem,,,,,,,) = originARM.baseAssetConfigs(address(woeth));
        buyPrice = buyPriceMem;
    }
}
