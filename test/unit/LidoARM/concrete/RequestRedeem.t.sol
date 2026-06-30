// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_LidoARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract Unit_LidoARM_RequestRedeem_Test is Unit_LidoARM_Shared_Test {
    using Math for uint256;

    function setUp() public override {
        super.setUp();
        desactiveCapManager();
        aliceFirstDeposit();
    }

    //////////////////////////////////////////////////////
    /// ---              Happy paths                   ---
    //////////////////////////////////////////////////////
    function test_RequestRedeem_Default() public {
        // Given: Alice already deposited 100 ether in setUp
        uint256 shares = 50 ether;
        uint256 expectedAssets = shares; // 1:1
        uint256 expectedRequestId = 0;
        uint256 expectedQueued = shares;
        uint256 expectedClaimTimestamp = block.timestamp + CLAIM_DELAY;

        assertEq(lidoARM.convertToAssets(shares), expectedAssets, "convertToAssets");
        assertEq(lidoARM.previewRedeem(shares), expectedAssets, "previewRedeem");
        assertEq(lidoARM.balanceOf(address(lidoARM)), 0, "escrow pre");
        assertEq(lidoARM.nextWithdrawalIndex(), 0, "nextIndex pre");
        assertEq(lidoARM.withdrawsQueuedShares(), 0, "queued pre");
        assertEq(lidoARM.reservedWithdrawLiquidity(), 0, "reserved pre");

        // Expect
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(alice, address(lidoARM), shares);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.RedeemRequested(
            alice, expectedRequestId, expectedAssets, expectedQueued, expectedClaimTimestamp
        );

        // When
        vm.prank(alice);
        (uint256 requestId, uint256 assets) = lidoARM.requestRedeem(shares);

        // Then
        assertEq(requestId, expectedRequestId, "requestId");
        assertEq(assets, expectedAssets, "assets");
        assertEq(lidoARM.balanceOf(alice), 100 ether - shares, "alice shares");
        assertEq(lidoARM.balanceOf(address(lidoARM)), shares, "escrow");
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY + 100 ether, "totalSupply");
        assertEq(lidoARM.nextWithdrawalIndex(), 1, "nextIndex");
        assertEq(lidoARM.withdrawsQueuedShares(), shares, "queued");
        assertEq(lidoARM.reservedWithdrawLiquidity(), expectedAssets, "reserved");

        // Stored withdrawal request
        _assertStoredRequest(expectedRequestId, alice, expectedClaimTimestamp, expectedAssets, expectedQueued, shares);
    }

    function test_RequestRedeem_WithYield() public {
        // Given: Alice already deposited 100 ether in setUp. Simulate yield accrued to the ARM by
        // donating WETH directly. totalSupply is unchanged, so the share price moves above 1.
        uint256 yield = 10.582931746103928574 ether;
        deal(address(weth), address(lidoARM), weth.balanceOf(address(lidoARM)) + yield);

        uint256 shares = 50 ether;
        uint256 expectedAssets =
            shares.mulDiv(MIN_TOTAL_SUPPLY + 100 ether + yield, MIN_TOTAL_SUPPLY + 100 ether, Math.Rounding.Floor);
        uint256 expectedClaimTimestamp = block.timestamp + CLAIM_DELAY;

        assertGt(expectedAssets, shares, "assets > shares");
        assertEq(lidoARM.convertToAssets(shares), expectedAssets, "convertToAssets");
        assertEq(lidoARM.previewRedeem(shares), expectedAssets, "previewRedeem");
        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY + 100 ether + yield, "totalAssets pre");
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY + 100 ether, "totalSupply pre");
        assertEq(lidoARM.nextWithdrawalIndex(), 0, "nextIndex pre");
        assertEq(lidoARM.withdrawsQueuedShares(), 0, "queued pre");
        assertEq(lidoARM.reservedWithdrawLiquidity(), 0, "reserved pre");

        // Expect
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(alice, address(lidoARM), shares);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.RedeemRequested(alice, 0, expectedAssets, shares, expectedClaimTimestamp);

        // When
        vm.prank(alice);
        (uint256 requestId, uint256 assets) = lidoARM.requestRedeem(shares);

        // Then
        assertEq(requestId, 0, "requestId");
        assertEq(assets, expectedAssets, "assets");
        assertEq(lidoARM.balanceOf(alice), 100 ether - shares, "alice shares");
        assertEq(lidoARM.balanceOf(address(lidoARM)), shares, "escrow");
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY + 100 ether, "totalSupply");
        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY + 100 ether + yield, "totalAssets");
        assertEq(lidoARM.nextWithdrawalIndex(), 1, "nextIndex");
        assertEq(lidoARM.withdrawsQueuedShares(), shares, "queued");
        assertEq(lidoARM.reservedWithdrawLiquidity(), expectedAssets, "reserved");

        // Stored withdrawal request
        _assertStoredRequest(0, alice, expectedClaimTimestamp, expectedAssets, shares, shares);
    }
}
