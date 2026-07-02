// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Fork_Shared_Test} from "test/fork/MultiAssetARM/shared/Shared.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

// Interfaces
import {IERC20, IWstETH, IWeETH} from "contracts/Interfaces.sol";

/// @notice Fork tests for `requestBaseAssetRedeem` on the MultiAssetARM. Each request opens real
///         withdrawal requests against the live Lido / Ether.fi queues (no finalization here).
contract Fork_Concrete_MultiAssetARM_RequestWithdraw_Test_ is Fork_Shared_Test {
    uint256 public constant AMOUNT = 100 ether;
    uint256 internal constant REBASE_TOLERANCE = 2;

    //////////////////////////////////////////////////////
    /// --- Lido (stETH / wstETH)
    //////////////////////////////////////////////////////
    function test_RequestWithdraw_stETH_SingleChunk() public {
        uint256 armBefore = steth.balanceOf(address(arm));

        vm.prank(operator);
        (uint256 sharesRequested, uint256 assetsExpected) = arm.requestBaseAssetRedeem(address(steth), AMOUNT);

        // stETH is pegged 1:1, so the request maps to a single sub-1000-ether Lido chunk.
        assertEq(sharesRequested, AMOUNT, "sharesRequested");
        assertEq(assetsExpected, AMOUNT, "assetsExpected");
        assertEq(_queue(steth).pendingRequestIdsLength(), 1, "one Lido chunk");
        assertEq(stethAssetAdapter.requestAssets(_queue(steth).pendingRequestId(0)), AMOUNT, "chunk amount");
        assertEq(_pendingRedeemAssets(steth), assetsExpected, "pendingRedeemAssets");
        assertApproxEqAbs(steth.balanceOf(address(arm)), armBefore - AMOUNT, REBASE_TOLERANCE, "ARM stETH drained");
    }

    function test_RequestWithdraw_stETH_MultiChunk() public {
        // 1500 stETH splits into Lido chunks of 1000 + 500.
        uint256 shares = 1_500 ether;

        vm.prank(operator);
        arm.requestBaseAssetRedeem(address(steth), shares);

        assertEq(_queue(steth).pendingRequestIdsLength(), 2, "two Lido chunks");
        assertEq(stethAssetAdapter.requestAssets(_queue(steth).pendingRequestId(0)), 1_000 ether, "chunk0");
        assertEq(stethAssetAdapter.requestAssets(_queue(steth).pendingRequestId(1)), 500 ether, "chunk1");
        assertEq(_pendingRedeemAssets(steth), shares, "pendingRedeemAssets");
    }

    function test_RequestWithdraw_wstETH_UnwrapsBeforeRequest() public {
        uint256 expectedStETH = IWstETH(address(wsteth)).getStETHByWstETH(AMOUNT);
        uint256 armBefore = wsteth.balanceOf(address(arm));

        vm.prank(operator);
        (uint256 sharesRequested, uint256 assetsExpected) = arm.requestBaseAssetRedeem(address(wsteth), AMOUNT);

        // wstETH unwraps to >1:1 stETH; the request still fits in a single chunk (~117 < 1000 ether).
        assertEq(sharesRequested, AMOUNT, "sharesRequested");
        assertApproxEqAbs(assetsExpected, expectedStETH, REBASE_TOLERANCE, "assetsExpected == unwrapped stETH");
        assertEq(_queue(wsteth).pendingRequestIdsLength(), 1, "one Lido chunk");
        assertEq(wsteth.balanceOf(address(arm)), armBefore - AMOUNT, "ARM wstETH drained");
        assertEq(_pendingRedeemAssets(wsteth), assetsExpected, "pendingRedeemAssets");
    }

    //////////////////////////////////////////////////////
    /// --- Ether.fi (eETH / weETH)
    //////////////////////////////////////////////////////
    function test_RequestWithdraw_eETH_MintsNFT() public {
        uint256 armBefore = eeth.balanceOf(address(arm));

        vm.prank(operator);
        (uint256 sharesRequested, uint256 assetsExpected) = arm.requestBaseAssetRedeem(address(eeth), AMOUNT);

        assertEq(sharesRequested, AMOUNT, "sharesRequested");
        assertEq(assetsExpected, AMOUNT, "assetsExpected");
        assertEq(_queue(eeth).pendingRequestIdsLength(), 1, "one EtherFi request");
        assertEq(_queue(eeth).requestShares(_queue(eeth).pendingRequestId(0)), AMOUNT, "request shares");
        assertEq(_pendingRedeemAssets(eeth), assetsExpected, "pendingRedeemAssets");
        assertApproxEqAbs(eeth.balanceOf(address(arm)), armBefore - AMOUNT, REBASE_TOLERANCE, "ARM eETH drained");
    }

    function test_RequestWithdraw_weETH_UnwrapsBeforeRequest() public {
        uint256 expectedEETH = IWeETH(address(weeth)).getEETHByWeETH(AMOUNT);
        uint256 armBefore = weeth.balanceOf(address(arm));

        vm.prank(operator);
        (uint256 sharesRequested, uint256 assetsExpected) = arm.requestBaseAssetRedeem(address(weeth), AMOUNT);

        assertEq(sharesRequested, AMOUNT, "sharesRequested");
        assertApproxEqAbs(assetsExpected, expectedEETH, REBASE_TOLERANCE, "assetsExpected == unwrapped eETH");
        assertEq(_queue(weeth).pendingRequestIdsLength(), 1, "one EtherFi request");
        assertEq(_queue(weeth).requestShares(_queue(weeth).pendingRequestId(0)), AMOUNT, "request shares");
        assertEq(weeth.balanceOf(address(arm)), armBefore - AMOUNT, "ARM weETH drained");
        assertEq(_pendingRedeemAssets(weeth), assetsExpected, "pendingRedeemAssets");
    }

    function test_RequestWithdraw_SecondRequest_Appends() public {
        vm.startPrank(operator);
        arm.requestBaseAssetRedeem(address(steth), AMOUNT);
        arm.requestBaseAssetRedeem(address(steth), 2 * AMOUNT);
        vm.stopPrank();

        assertEq(_queue(steth).pendingRequestIdsLength(), 2, "two pending requests");
        assertEq(_pendingRedeemAssets(steth), 3 * AMOUNT, "pendingRedeemAssets accumulates");
    }

    //////////////////////////////////////////////////////
    /// --- REVERT TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_RequestWithdraw_NotOperatorOrOwner() public {
        vm.expectRevert(bytes4(keccak256("OnlyOperatorOrOwner()")));
        arm.requestBaseAssetRedeem(address(steth), AMOUNT);
    }

    function test_RevertWhen_RequestWithdraw_UnsupportedAsset() public {
        vm.prank(operator);
        vm.expectRevert(AbstractARM.UnsupportedAsset.selector);
        arm.requestBaseAssetRedeem(address(badToken), AMOUNT);
    }

    function test_RevertWhen_RequestWithdraw_ZeroShares() public {
        vm.prank(operator);
        vm.expectRevert("Adapter: zero shares");
        arm.requestBaseAssetRedeem(address(steth), 0);
    }

    function test_RevertWhen_RequestWithdraw_DirectAdapterCall_NotARM() public {
        vm.prank(operator);
        vm.expectRevert("Adapter: only ARM");
        stethAssetAdapter.requestRedeem(AMOUNT);
    }
}
