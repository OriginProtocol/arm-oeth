// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_EtherARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract Unit_EtherARM_RequestRedeem_Test is Unit_EtherARM_Shared_Test {
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

        assertEq(etherARM.convertToAssets(shares), expectedAssets, "convertToAssets");
        assertEq(etherARM.previewRedeem(shares), expectedAssets, "previewRedeem");
        assertEq(etherARM.balanceOf(address(etherARM)), 0, "escrow pre");
        assertEq(etherARM.nextWithdrawalIndex(), 0, "nextIndex pre");
        assertEq(etherARM.withdrawsQueuedShares(), 0, "queued pre");
        assertEq(etherARM.reservedWithdrawLiquidity(), 0, "reserved pre");

        // Expect
        vm.expectEmit({emitter: address(etherARM)});
        emit IERC20.Transfer(alice, address(etherARM), shares);
        vm.expectEmit({emitter: address(etherARM)});
        emit AbstractARM.RedeemRequested(
            alice, expectedRequestId, expectedAssets, expectedQueued, expectedClaimTimestamp
        );

        // When
        vm.prank(alice);
        (uint256 requestId, uint256 assets) = etherARM.requestRedeem(shares);

        // Then
        assertEq(requestId, expectedRequestId, "requestId");
        assertEq(assets, expectedAssets, "assets");
        assertEq(etherARM.balanceOf(alice), 100 ether - shares, "alice shares");
        assertEq(etherARM.balanceOf(address(etherARM)), shares, "escrow");
        assertEq(etherARM.totalSupply(), 1e12 + 100 ether, "totalSupply");
        assertEq(etherARM.nextWithdrawalIndex(), 1, "nextIndex");
        assertEq(etherARM.withdrawsQueuedShares(), shares, "queued");
        assertEq(etherARM.reservedWithdrawLiquidity(), expectedAssets, "reserved");

        // Stored withdrawal request
        _assertStoredRequest(expectedRequestId, alice, expectedClaimTimestamp, expectedAssets, expectedQueued, shares);
    }

    function test_RequestRedeem_WithYield() public {
        // Given: Alice already deposited 100 ether in setUp. Simulate yield accrued to the ARM by
        // donating WETH directly. totalSupply is unchanged, so the share price moves above 1.
        uint256 yield = 10.582931746103928574 ether;
        deal(address(weth), address(etherARM), weth.balanceOf(address(etherARM)) + yield);

        uint256 shares = 50 ether;
        uint256 expectedAssets = shares.mulDiv(1e12 + 100 ether + yield, 1e12 + 100 ether, Math.Rounding.Floor);
        uint256 expectedClaimTimestamp = block.timestamp + CLAIM_DELAY;

        assertGt(expectedAssets, shares, "assets > shares");
        assertEq(etherARM.convertToAssets(shares), expectedAssets, "convertToAssets");
        assertEq(etherARM.previewRedeem(shares), expectedAssets, "previewRedeem");
        assertEq(etherARM.totalAssets(), 1e12 + 100 ether + yield, "totalAssets pre");
        assertEq(etherARM.totalSupply(), 1e12 + 100 ether, "totalSupply pre");
        assertEq(etherARM.nextWithdrawalIndex(), 0, "nextIndex pre");
        assertEq(etherARM.withdrawsQueuedShares(), 0, "queued pre");
        assertEq(etherARM.reservedWithdrawLiquidity(), 0, "reserved pre");

        // Expect
        vm.expectEmit({emitter: address(etherARM)});
        emit IERC20.Transfer(alice, address(etherARM), shares);
        vm.expectEmit({emitter: address(etherARM)});
        emit AbstractARM.RedeemRequested(alice, 0, expectedAssets, shares, expectedClaimTimestamp);

        // When
        vm.prank(alice);
        (uint256 requestId, uint256 assets) = etherARM.requestRedeem(shares);

        // Then
        assertEq(requestId, 0, "requestId");
        assertEq(assets, expectedAssets, "assets");
        assertEq(etherARM.balanceOf(alice), 100 ether - shares, "alice shares");
        assertEq(etherARM.balanceOf(address(etherARM)), shares, "escrow");
        assertEq(etherARM.totalSupply(), 1e12 + 100 ether, "totalSupply");
        assertEq(etherARM.totalAssets(), 1e12 + 100 ether + yield, "totalAssets");
        assertEq(etherARM.nextWithdrawalIndex(), 1, "nextIndex");
        assertEq(etherARM.withdrawsQueuedShares(), shares, "queued");
        assertEq(etherARM.reservedWithdrawLiquidity(), expectedAssets, "reserved");

        // Stored withdrawal request
        _assertStoredRequest(0, alice, expectedClaimTimestamp, expectedAssets, shares, shares);
    }
}
