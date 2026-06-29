// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_EtherARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";
import {OwnableOperable} from "contracts/OwnableOperable.sol";

/// @notice Tests the ARM-side flow of `requestBaseAssetRedeem` and `claimBaseAssetRedeem` for
///         both stETH (1:1 adapter) and wstETH (ERC4626-style adapter with a non-1:1 unwrap).
///         The adapter's internal queue logic is covered separately; here we only assert the
///         ARM's accounting (`pendingRedeemAssets`, `totalAssets`), access control, and that
///         funds move between ARM, adapter, and the Lido withdrawal queue as expected.
contract Unit_EtherARM_BaseAssetRedeem_Test is Unit_EtherARM_Shared_Test {
    uint256 internal constant ARM_STETH_BALANCE = 100 ether;
    uint256 internal constant ARM_WSTETH_BALANCE = 100 ether;

    function setUp() public override {
        super.setUp();
        desactiveCapManager();

        // stETH base asset (1:1 adapter).
        addBaseAsset(steth);
        deal(address(steth), address(etherARM), ARM_STETH_BALANCE);

        // wstETH base asset. Apply the 1 wstETH = 1.237 stETH rate so the non-1:1 unwrap is exercised,
        // then seed the ARM via the ERC4626 mint path — `deal` on wstETH would desync vault accounting.
        addBaseAsset(wsteth);
        seedWstETHWithTargetExchangeRate();
        dealWsteth(address(etherARM), ARM_WSTETH_BALANCE);
    }

    //////////////////////////////////////////////////////
    /// --- requestBaseAssetRedeem
    //////////////////////////////////////////////////////
    function test_RequestBaseAssetRedeem_Default() public {
        uint256 shares = 50 ether;
        uint256 totalAssetsBefore = etherARM.totalAssets();

        // Pre-conditions
        assertEq(steth.balanceOf(address(etherARM)), ARM_STETH_BALANCE, "ARM stETH pre");
        assertEq(steth.balanceOf(address(stETHAssetAdapter)), 0, "adapter stETH pre");
        assertEq(steth.balanceOf(address(lidoWithdrawalQueue)), 0, "queue stETH pre");
        assertEq(pendingRedeemAssets(steth), 0, "pendingRedeemAssets pre");
        assertEq(lidoWithdrawalQueue.counter(), 0, "queue counter pre");

        // When
        vm.prank(operator);
        (uint256 sharesRequested, uint256 assetsExpected) = etherARM.requestBaseAssetRedeem(address(steth), shares);

        // Then — return values (stETH adapter is 1:1)
        assertEq(sharesRequested, shares, "sharesRequested");
        assertEq(assetsExpected, shares, "assetsExpected");

        // Flow of funds: stETH leaves the ARM and lands in the withdrawal queue, not the adapter.
        assertEq(steth.balanceOf(address(etherARM)), ARM_STETH_BALANCE - shares, "ARM stETH post");
        assertEq(steth.balanceOf(address(stETHAssetAdapter)), 0, "adapter stETH post");
        assertEq(steth.balanceOf(address(lidoWithdrawalQueue)), shares, "queue stETH post");

        // ARM accounting: the in-flight redeem replaces the on-hand stETH 1:1 in totalAssets().
        assertEq(pendingRedeemAssets(steth), shares, "pendingRedeemAssets post");
        assertEq(etherARM.totalAssets(), totalAssetsBefore, "totalAssets preserved");

        // The mock withdrawal queue recorded the request against the adapter.
        assertEq(lidoWithdrawalQueue.counter(), 1, "queue counter post");
        (address requestOwner, uint256 requestAmount, bool claimed, bool finalized) = lidoWithdrawalQueue.requests(0);
        assertEq(requestOwner, address(stETHAssetAdapter), "request.owner");
        assertEq(requestAmount, shares, "request.amount");
        assertEq(claimed, false, "request.claimed");
        assertEq(finalized, true, "request.finalized");
    }

    function test_RequestBaseAssetRedeem_Wsteth() public {
        uint256 shares = 50 ether;
        // wstETH is ERC4626-style: shares (wstETH) and assets (stETH-equivalent) diverge by the exchange rate.
        uint256 expectedStETH = mockWstETH.getStETHByWstETH(shares);
        uint256 totalAssetsBefore = etherARM.totalAssets();

        // Pre-conditions
        assertEq(wsteth.balanceOf(address(etherARM)), ARM_WSTETH_BALANCE, "ARM wstETH pre");
        assertEq(wsteth.balanceOf(address(wstETHAssetAdapter)), 0, "adapter wstETH pre");
        assertEq(steth.balanceOf(address(wstETHAssetAdapter)), 0, "adapter stETH pre");
        assertEq(steth.balanceOf(address(lidoWithdrawalQueue)), 0, "queue stETH pre");
        assertEq(pendingRedeemAssets(wsteth), 0, "pendingRedeemAssets pre");
        assertEq(lidoWithdrawalQueue.counter(), 0, "queue counter pre");

        // When
        vm.prank(operator);
        (uint256 sharesRequested, uint256 assetsExpected) = etherARM.requestBaseAssetRedeem(address(wsteth), shares);

        // Then — return values: shares are wstETH (1:1 with the request), assets expand by exchange rate.
        assertEq(sharesRequested, shares, "sharesRequested");
        assertEq(assetsExpected, expectedStETH, "assetsExpected");

        // Flow of funds: wstETH leaves the ARM, gets unwrapped to stETH, and stETH lands in the queue.
        assertEq(wsteth.balanceOf(address(etherARM)), ARM_WSTETH_BALANCE - shares, "ARM wstETH post");
        assertEq(wsteth.balanceOf(address(wstETHAssetAdapter)), 0, "adapter wstETH post");
        assertEq(steth.balanceOf(address(wstETHAssetAdapter)), 0, "adapter stETH post");
        assertEq(steth.balanceOf(address(lidoWithdrawalQueue)), expectedStETH, "queue stETH post");

        // ARM accounting: pending is tracked in liquidity (stETH) terms; totalAssets preserved because
        // the wstETH lost from the ARM balance is matched by the same stETH-equivalent in pending.
        assertEq(pendingRedeemAssets(wsteth), expectedStETH, "pendingRedeemAssets post");
        assertEq(etherARM.totalAssets(), totalAssetsBefore, "totalAssets preserved");

        // The mock withdrawal queue recorded the request against the adapter, in stETH units.
        assertEq(lidoWithdrawalQueue.counter(), 1, "queue counter post");
        (address requestOwner, uint256 requestAmount, bool claimed, bool finalized) = lidoWithdrawalQueue.requests(0);
        assertEq(requestOwner, address(wstETHAssetAdapter), "request.owner");
        assertEq(requestAmount, expectedStETH, "request.amount");
        assertEq(claimed, false, "request.claimed");
        assertEq(finalized, true, "request.finalized");
    }

    function test_RequestBaseAssetRedeem_RevertWhen_UnsupportedAsset() public {
        // weth is the liquidity asset; it has no adapter registered.
        vm.prank(operator);
        vm.expectRevert(AbstractARM.UnsupportedAsset.selector);
        etherARM.requestBaseAssetRedeem(address(weth), 1 ether);
    }

    function test_RequestBaseAssetRedeem_RevertWhen_NotAuthorized() public {
        vm.prank(alice);
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        etherARM.requestBaseAssetRedeem(address(steth), 1 ether);
    }

    //////////////////////////////////////////////////////
    /// --- claimBaseAssetRedeem
    //////////////////////////////////////////////////////
    function test_ClaimBaseAssetRedeem_Default() public {
        uint256 shares = 50 ether;

        // Given: a redeem has already been requested.
        vm.prank(operator);
        etherARM.requestBaseAssetRedeem(address(steth), shares);

        uint256 totalAssetsBefore = etherARM.totalAssets();
        uint256 armWethBefore = weth.balanceOf(address(etherARM));

        assertEq(pendingRedeemAssets(steth), shares, "pendingRedeemAssets pre claim");
        assertEq(steth.balanceOf(address(lidoWithdrawalQueue)), shares, "queue stETH pre claim");

        // When
        vm.prank(operator);
        (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived) =
            etherARM.claimBaseAssetRedeem(address(steth), shares);

        // Then — return values
        assertEq(sharesClaimed, shares, "sharesClaimed");
        assertEq(assetsExpected, shares, "assetsExpected");
        assertEq(assetsReceived, shares, "assetsReceived");

        // Flow of funds: WETH ends up in the ARM, adapter holds no residual ETH or WETH.
        assertEq(weth.balanceOf(address(etherARM)), armWethBefore + shares, "ARM weth post");
        assertEq(weth.balanceOf(address(stETHAssetAdapter)), 0, "adapter weth post");
        assertEq(address(stETHAssetAdapter).balance, 0, "adapter eth post");

        // ARM accounting: pending cleared, totalAssets unchanged across the full cycle.
        assertEq(pendingRedeemAssets(steth), 0, "pendingRedeemAssets post");
        assertEq(etherARM.totalAssets(), totalAssetsBefore, "totalAssets preserved");

        // The mock marked the request as claimed.
        (,, bool claimed,) = lidoWithdrawalQueue.requests(0);
        assertEq(claimed, true, "request.claimed");
    }

    function test_ClaimBaseAssetRedeem_Wsteth() public {
        uint256 shares = 50 ether;
        uint256 expectedStETH = mockWstETH.getStETHByWstETH(shares);

        // Given: a redeem has already been requested.
        vm.prank(operator);
        etherARM.requestBaseAssetRedeem(address(wsteth), shares);

        uint256 totalAssetsBefore = etherARM.totalAssets();
        uint256 armWethBefore = weth.balanceOf(address(etherARM));

        assertEq(pendingRedeemAssets(wsteth), expectedStETH, "pendingRedeemAssets pre claim");
        assertEq(steth.balanceOf(address(lidoWithdrawalQueue)), expectedStETH, "queue stETH pre claim");

        // When
        vm.prank(operator);
        (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived) =
            etherARM.claimBaseAssetRedeem(address(wsteth), shares);

        // Then — return values
        assertEq(sharesClaimed, shares, "sharesClaimed");
        assertEq(assetsExpected, expectedStETH, "assetsExpected");
        assertEq(assetsReceived, expectedStETH, "assetsReceived");

        // Flow of funds: WETH ends up in the ARM, adapter holds no residual ETH or WETH.
        assertEq(weth.balanceOf(address(etherARM)), armWethBefore + expectedStETH, "ARM weth post");
        assertEq(weth.balanceOf(address(wstETHAssetAdapter)), 0, "adapter weth post");
        assertEq(address(wstETHAssetAdapter).balance, 0, "adapter eth post");

        // ARM accounting: pending cleared, totalAssets unchanged across the full cycle.
        assertEq(pendingRedeemAssets(wsteth), 0, "pendingRedeemAssets post");
        assertEq(etherARM.totalAssets(), totalAssetsBefore, "totalAssets preserved");

        // The mock marked the request as claimed.
        (,, bool claimed,) = lidoWithdrawalQueue.requests(0);
        assertEq(claimed, true, "request.claimed");
    }

    function test_ClaimBaseAssetRedeem_RevertWhen_UnsupportedAsset() public {
        vm.prank(operator);
        vm.expectRevert(AbstractARM.UnsupportedAsset.selector);
        etherARM.claimBaseAssetRedeem(address(weth), 1 ether);
    }

    function test_ClaimBaseAssetRedeem_RevertWhen_NotAuthorized() public {
        vm.prank(alice);
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        etherARM.claimBaseAssetRedeem(address(steth), 1 ether);
    }
}
