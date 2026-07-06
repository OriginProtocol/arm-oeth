// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_MultiAssetARM_Shared_Test} from "../Shared.t.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";
import {OwnableOperable} from "contracts/OwnableOperable.sol";
import {IERC20} from "contracts/Interfaces.sol";

/// @notice Adapter redemption flow (request/claim) through MockAssetAdapter, run at both 18 and 6 decimal
///         liquidity, across 6 and 18 decimal base assets. `assetsExpected` / `pendingRedeemAssets` are tracked
///         in the liquidity asset's decimals.
abstract contract BaseAssetRedeem_Test is Unit_MultiAssetARM_Shared_Test {
    function setUp() public virtual override {
        super.setUp();
        desactiveCapManager();
    }

    function _runRequestClaim(IERC20 base, address adapter, uint256 baseAmount) internal {
        dealBaseToARM(base, baseAmount);
        uint256 expectedAssets = _scaleBaseToLiquidity(base, baseAmount); // rate == 1

        vm.prank(operator);
        (uint256 sharesRequested, uint256 assetsExpected) = arm.requestBaseAssetRedeem(address(base), baseAmount);
        assertEq(sharesRequested, baseAmount, "shares requested");
        assertEq(assetsExpected, expectedAssets, "assets expected (liquidity decimals)");
        assertEq(pendingRedeemAssets(base), expectedAssets, "pendingRedeemAssets");
        assertEq(base.balanceOf(address(arm)), 0, "base pulled from ARM");
        assertEq(base.balanceOf(adapter), baseAmount, "adapter holds base");

        uint256 armBefore = liquidity.balanceOf(address(arm));
        vm.prank(operator);
        (uint256 sharesClaimed,, uint256 received) = arm.claimBaseAssetRedeem(address(base), baseAmount);
        assertEq(sharesClaimed, baseAmount, "shares claimed");
        assertEq(received, expectedAssets, "received (liquidity decimals)");
        assertEq(liquidity.balanceOf(address(arm)) - armBefore, expectedAssets, "ARM received liquidity");
        assertEq(pendingRedeemAssets(base), 0, "pending cleared");
    }

    function test_RequestAndClaim_Adapter18Decimals() public {
        _runRequestClaim(adp18, address(adapterAdp18), 100e18);
    }

    function test_RequestAndClaim_Adapter6Decimals() public {
        _runRequestClaim(adp6, address(adapterAdp6), 100e6);
    }

    function test_Claim_WithShortfall_ReflectsLoss() public {
        adapterAdp18.setShortfallBps(100); // deliver 99%
        dealBaseToARM(adp18, 100e18);
        uint256 expected = _scaleBaseToLiquidity(adp18, 100e18);

        vm.prank(operator);
        arm.requestBaseAssetRedeem(address(adp18), 100e18);

        uint256 totalBefore = arm.totalAssets();
        vm.prank(operator);
        (,, uint256 received) = arm.claimBaseAssetRedeem(address(adp18), 100e18);

        assertEq(received, expected * 99 / 100, "1% shortfall delivered");
        assertEq(pendingRedeemAssets(adp18), 0, "pending removed at expected value");
        // Pending (expected) removed, only 99% received => totalAssets drops by the 1% shortfall.
        assertEq(arm.totalAssets(), totalBefore - (expected - expected * 99 / 100), "loss reflected in totalAssets");
    }

    function test_RequestBaseAssetRedeem_RevertWhen_NotAuthorized() public {
        dealBaseToARM(adp18, 100e18);
        vm.prank(alice);
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        arm.requestBaseAssetRedeem(address(adp18), 100e18);
    }

    function test_RequestBaseAssetRedeem_RevertWhen_Unsupported() public {
        vm.prank(operator);
        vm.expectRevert(AbstractARM.UnsupportedAsset.selector);
        arm.requestBaseAssetRedeem(makeAddr("random"), 1e18);
    }
}

contract BaseAssetRedeem_18dec_Test is BaseAssetRedeem_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 18;
    }
}

contract BaseAssetRedeem_6dec_Test is BaseAssetRedeem_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 6;
    }
}
