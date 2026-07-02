// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_MultiAssetARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @author Origin Protocol Inc
/// @notice Fuzzes LP redeem requests across share counts, yield levels, and sequential request splits
///         to confirm the request struct, cumulative `queued` tracking, and `reservedWithdrawLiquidity`
///         all stay consistent.
contract Unit_Fuzz_MultiAssetARM_RequestRedeem_Test is Unit_MultiAssetARM_Shared_Test {
    using Math for uint256;

    //////////////////////////////////////////////////////
    /// ---                  SETUP                     ---
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();
        desactiveCapManager();
        aliceFirstDeposit(100 ether);
    }

    //////////////////////////////////////////////////////
    /// ---             Fuzz share count               ---
    //////////////////////////////////////////////////////
    function testFuzz_RequestRedeem_Shares(uint128 fuzzedShares) public {
        // requestRedeem does not enforce MIN_SHARES_TO_REDEEM, so the lower bound is 1 wei.
        uint256 shares = _bound(uint256(fuzzedShares), 1, arm.balanceOf(alice));

        uint256 supplyBefore = arm.totalSupply();
        uint256 assetsBefore = arm.totalAssets();
        uint256 expectedAssets = shares.mulDiv(assetsBefore, supplyBefore, Math.Rounding.Floor);
        uint256 expectedClaimTimestamp = block.timestamp + CLAIM_DELAY;

        assertEq(arm.previewRedeem(shares), expectedAssets, "previewRedeem");

        // Expect events
        vm.expectEmit({emitter: address(arm)});
        emit IERC20.Transfer(alice, address(arm), shares);
        vm.expectEmit({emitter: address(arm)});
        emit AbstractARM.RedeemRequested(alice, 0, expectedAssets, shares, expectedClaimTimestamp);

        // When
        vm.prank(alice);
        (uint256 requestId, uint256 assets) = arm.requestRedeem(shares);

        // Then
        assertEq(requestId, 0, "requestId");
        assertEq(assets, expectedAssets, "assets returned");
        assertEq(arm.balanceOf(alice), 100 ether - shares, "alice shares");
        assertEq(arm.balanceOf(address(arm)), shares, "escrow");
        assertEq(arm.totalSupply(), supplyBefore, "totalSupply unchanged");
        assertEq(arm.totalAssets(), assetsBefore, "totalAssets unchanged");
        assertEq(arm.nextWithdrawalIndex(), 1, "nextWithdrawalIndex");
        assertEq(arm.withdrawsQueuedShares(), shares, "withdrawsQueuedShares");
        assertEq(arm.reservedWithdrawLiquidity(), expectedAssets, "reservedWithdrawLiquidity");

        _assertStoredRequest(0, alice, expectedClaimTimestamp, expectedAssets, shares, shares);
    }

    //////////////////////////////////////////////////////
    /// ---             Fuzz yield level               ---
    //////////////////////////////////////////////////////
    function testFuzz_RequestRedeem_Yield(uint128 fuzzedYield) public {
        // Lower bound at 1 ether so the share-price uplift is large enough to survive truncation on
        // a 50 ether redeem (otherwise expectedAssets == shares). Upper bound at uint96.max so the
        // SafeCast on `assets` inside requestRedeem (l. 787) never reverts.
        uint256 yield = _bound(uint256(fuzzedYield), 1 ether, type(uint96).max);
        deal(address(liquidity), address(arm), liquidity.balanceOf(address(arm)) + yield);

        uint256 shares = 50 ether;
        uint256 supplyBefore = arm.totalSupply();
        uint256 assetsBefore = arm.totalAssets();
        uint256 expectedAssets = shares.mulDiv(assetsBefore, supplyBefore, Math.Rounding.Floor);
        uint256 expectedClaimTimestamp = block.timestamp + CLAIM_DELAY;

        // Property: yield > 0 ⇒ assets per share > 1 ⇒ expectedAssets > shares for non-truncating yields.
        assertGt(expectedAssets, shares, "yield should grow assets above shares");

        assertEq(arm.previewRedeem(shares), expectedAssets, "previewRedeem");

        // Expect events
        vm.expectEmit({emitter: address(arm)});
        emit IERC20.Transfer(alice, address(arm), shares);
        vm.expectEmit({emitter: address(arm)});
        emit AbstractARM.RedeemRequested(alice, 0, expectedAssets, shares, expectedClaimTimestamp);

        // When
        vm.prank(alice);
        (uint256 requestId, uint256 assets) = arm.requestRedeem(shares);

        // Then
        assertEq(requestId, 0, "requestId");
        assertEq(assets, expectedAssets, "assets returned");
        assertEq(arm.balanceOf(alice), 100 ether - shares, "alice shares");
        assertEq(arm.balanceOf(address(arm)), shares, "escrow");
        assertEq(arm.totalSupply(), supplyBefore, "totalSupply unchanged");
        assertEq(arm.totalAssets(), assetsBefore, "totalAssets unchanged");
        assertEq(arm.nextWithdrawalIndex(), 1, "nextWithdrawalIndex");
        assertEq(arm.withdrawsQueuedShares(), shares, "withdrawsQueuedShares");
        assertEq(arm.reservedWithdrawLiquidity(), expectedAssets, "reservedWithdrawLiquidity");

        _assertStoredRequest(0, alice, expectedClaimTimestamp, expectedAssets, shares, shares);
    }

    //////////////////////////////////////////////////////
    /// ---     Fuzz split between two requests        ---
    //////////////////////////////////////////////////////
    function testFuzz_RequestRedeem_Sequential(uint128 fuzzedSplit) public {
        // Two consecutive requests sharing alice's 100 ether of shares. Probes the cumulative `queued`
        // tracking used by the FIFO gate at claim time.
        uint256 totalShares = 100 ether;
        uint256 firstShares = _bound(uint256(fuzzedSplit), 1, totalShares - 1);
        uint256 secondShares = totalShares - firstShares;

        uint256 expectedClaimTimestamp = block.timestamp + CLAIM_DELAY;

        // First request
        vm.expectEmit({emitter: address(arm)});
        emit IERC20.Transfer(alice, address(arm), firstShares);
        vm.expectEmit({emitter: address(arm)});
        emit AbstractARM.RedeemRequested(alice, 0, firstShares, firstShares, expectedClaimTimestamp);

        vm.prank(alice);
        (uint256 firstRequestId, uint256 firstAssets) = arm.requestRedeem(firstShares);

        // Second request
        vm.expectEmit({emitter: address(arm)});
        emit IERC20.Transfer(alice, address(arm), secondShares);
        vm.expectEmit({emitter: address(arm)});
        emit AbstractARM.RedeemRequested(alice, 1, secondShares, totalShares, expectedClaimTimestamp);

        vm.prank(alice);
        (uint256 secondRequestId, uint256 secondAssets) = arm.requestRedeem(secondShares);

        // Then
        assertEq(firstRequestId, 0, "firstRequestId");
        assertEq(firstAssets, firstShares, "firstAssets at 1:1");
        assertEq(secondRequestId, 1, "secondRequestId");
        assertEq(secondAssets, secondShares, "secondAssets at 1:1");

        assertEq(arm.balanceOf(alice), 0, "alice shares");
        assertEq(arm.balanceOf(address(arm)), totalShares, "escrow");
        assertEq(arm.nextWithdrawalIndex(), 2, "nextWithdrawalIndex");
        assertEq(arm.withdrawsQueuedShares(), totalShares, "withdrawsQueuedShares");
        assertEq(arm.reservedWithdrawLiquidity(), totalShares, "reservedWithdrawLiquidity");

        // First request: queued cumulative == firstShares.
        _assertStoredRequest(0, alice, expectedClaimTimestamp, firstShares, firstShares, firstShares);
        // Second request: queued cumulative == totalShares (firstShares + secondShares).
        _assertStoredRequest(1, alice, expectedClaimTimestamp, secondShares, totalShares, secondShares);
    }
}
