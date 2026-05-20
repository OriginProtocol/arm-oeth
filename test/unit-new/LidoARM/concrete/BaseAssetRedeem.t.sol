// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_LidoARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";
import {OwnableOperable} from "contracts/OwnableOperable.sol";


/// @notice Tests the ARM-side flow of `requestBaseAssetRedeem` and `claimBaseAssetRedeem`.
///         The adapter's internal queue logic is covered separately; here we only assert the
///         ARM's accounting (`pendingRedeemAssets`, `totalAssets`), access control, and that
///         funds move between ARM, adapter, and the Lido withdrawal queue as expected.
contract Unit_LidoARM_BaseAssetRedeem_Test is Unit_LidoARM_Shared_Test {
    uint256 internal constant ARM_STETH_BALANCE = 100 ether;

    function setUp() public override {
        super.setUp();
        desactiveCapManager();
        addBaseAsset(steth);
        // Seed the ARM with stETH that the operator can route through the adapter.
        deal(address(steth), address(lidoARM), ARM_STETH_BALANCE);
    }

    //////////////////////////////////////////////////////
    /// --- requestBaseAssetRedeem
    //////////////////////////////////////////////////////
    function test_RequestBaseAssetRedeem_Default() public {
        uint256 shares = 50 ether;
        uint256 totalAssetsBefore = lidoARM.totalAssets();

        // Pre-conditions
        assertEq(steth.balanceOf(address(lidoARM)), ARM_STETH_BALANCE, "ARM stETH pre");
        assertEq(steth.balanceOf(address(stETHAssetAdapter)), 0, "adapter stETH pre");
        assertEq(steth.balanceOf(address(lidoWithdrawalQueue)), 0, "queue stETH pre");
        assertEq(pendingRedeemAssets(steth), 0, "pendingRedeemAssets pre");
        assertEq(lidoWithdrawalQueue.counter(), 0, "queue counter pre");

        // When
        vm.prank(operator);
        (uint256 sharesRequested, uint256 assetsExpected) =
            lidoARM.requestBaseAssetRedeem(address(steth), shares);

        // Then — return values (stETH adapter is 1:1)
        assertEq(sharesRequested, shares, "sharesRequested");
        assertEq(assetsExpected, shares, "assetsExpected");

        // Flow of funds: stETH leaves the ARM and lands in the withdrawal queue, not the adapter.
        assertEq(steth.balanceOf(address(lidoARM)), ARM_STETH_BALANCE - shares, "ARM stETH post");
        assertEq(steth.balanceOf(address(stETHAssetAdapter)), 0, "adapter stETH post");
        assertEq(steth.balanceOf(address(lidoWithdrawalQueue)), shares, "queue stETH post");

        // ARM accounting: the in-flight redeem replaces the on-hand stETH 1:1 in totalAssets().
        assertEq(pendingRedeemAssets(steth), shares, "pendingRedeemAssets post");
        assertEq(lidoARM.totalAssets(), totalAssetsBefore, "totalAssets preserved");

        // The mock withdrawal queue recorded the request against the adapter.
        assertEq(lidoWithdrawalQueue.counter(), 1, "queue counter post");
        (address requestOwner, uint256 requestAmount, bool claimed, bool finalized) =
            lidoWithdrawalQueue.requests(0);
        assertEq(requestOwner, address(stETHAssetAdapter), "request.owner");
        assertEq(requestAmount, shares, "request.amount");
        assertEq(claimed, false, "request.claimed");
        assertEq(finalized, true, "request.finalized");
    }

    function test_RequestBaseAssetRedeem_RevertWhen_UnsupportedAsset() public {
        // weth is the liquidity asset; it has no adapter registered.
        vm.prank(operator);
        vm.expectRevert(AbstractARM.UnsupportedAsset.selector);
        lidoARM.requestBaseAssetRedeem(address(weth), 1 ether);
    }

    function test_RequestBaseAssetRedeem_RevertWhen_NotAuthorized() public {
        vm.prank(alice);
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        lidoARM.requestBaseAssetRedeem(address(steth), 1 ether);
    }

    //////////////////////////////////////////////////////
    /// --- claimBaseAssetRedeem
    //////////////////////////////////////////////////////
    function test_ClaimBaseAssetRedeem_Default() public {
        uint256 shares = 50 ether;

        // Given: a redeem has already been requested.
        vm.prank(operator);
        lidoARM.requestBaseAssetRedeem(address(steth), shares);

        uint256 totalAssetsBefore = lidoARM.totalAssets();
        uint256 armWethBefore = weth.balanceOf(address(lidoARM));

        assertEq(pendingRedeemAssets(steth), shares, "pendingRedeemAssets pre claim");
        assertEq(steth.balanceOf(address(lidoWithdrawalQueue)), shares, "queue stETH pre claim");

        // When
        vm.prank(operator);
        (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived) =
            lidoARM.claimBaseAssetRedeem(address(steth), shares);

        // Then — return values
        assertEq(sharesClaimed, shares, "sharesClaimed");
        assertEq(assetsExpected, shares, "assetsExpected");
        assertEq(assetsReceived, shares, "assetsReceived");

        // Flow of funds: WETH ends up in the ARM, adapter holds no residual ETH or WETH.
        assertEq(weth.balanceOf(address(lidoARM)), armWethBefore + shares, "ARM weth post");
        assertEq(weth.balanceOf(address(stETHAssetAdapter)), 0, "adapter weth post");
        assertEq(address(stETHAssetAdapter).balance, 0, "adapter eth post");

        // ARM accounting: pending cleared, totalAssets unchanged across the full cycle.
        assertEq(pendingRedeemAssets(steth), 0, "pendingRedeemAssets post");
        assertEq(lidoARM.totalAssets(), totalAssetsBefore, "totalAssets preserved");

        // The mock marked the request as claimed.
        (,, bool claimed,) = lidoWithdrawalQueue.requests(0);
        assertEq(claimed, true, "request.claimed");
    }

    function test_ClaimBaseAssetRedeem_RevertWhen_UnsupportedAsset() public {
        vm.prank(operator);
        vm.expectRevert(AbstractARM.UnsupportedAsset.selector);
        lidoARM.claimBaseAssetRedeem(address(weth), 1 ether);
    }

    function test_ClaimBaseAssetRedeem_RevertWhen_NotAuthorized() public {
        vm.prank(alice);
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        lidoARM.claimBaseAssetRedeem(address(steth), 1 ether);
    }
}
