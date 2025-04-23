// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";
import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";

contract Unit_Concrete_OriginARM_RequestRedeem_Test_ is Unit_Shared_Test {
    using SafeCast for int256;
    using SafeCast for int128;

    function setUp() public virtual override {
        super.setUp();

        // Give Alice some WETH
        deal(address(weth), alice, 1_000 * DEFAULT_AMOUNT);
        // Alice approve max WETH to the ARM
        vm.startPrank(alice);
        weth.approve(address(originARM), type(uint256).max);
        originARM.deposit(DEFAULT_AMOUNT);
        vm.stopPrank();
    }

    function test_RequestRedeem() public {
        // Expected values
        uint256 expectedShares = originARM.convertToShares(DEFAULT_AMOUNT);
        uint256 expectedOETH = originARM.convertToAssets(expectedShares);
        uint256 requestIndex = originARM.nextWithdrawalIndex();
        uint128 queued = originARM.withdrawsQueued();
        int128 lastAvailableAssets = originARM.lastAvailableAssets();

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.RedeemRequested(alice, 0, expectedOETH, DEFAULT_AMOUNT, block.timestamp + CLAIM_DELAY);

        // Alice requests a redeem of 1 WETH
        vm.prank(alice);
        originARM.requestRedeem(DEFAULT_AMOUNT);

        (address withdrawer, bool claimed, uint256 requestTimestamp, uint256 amount, uint256 queued_) =
            originARM.withdrawalRequests(0);
        // Assertions
        assertEq(
            originARM.lastAvailableAssets().toUint256(),
            lastAvailableAssets.toUint256() - DEFAULT_AMOUNT,
            "Last available assets should be updated"
        );
        assertEq(originARM.withdrawsQueued(), queued + DEFAULT_AMOUNT, "Withdraws queued should be updated");
        assertEq(originARM.nextWithdrawalIndex(), requestIndex + 1, "Next withdrawal index should be updated");
        assertEq(withdrawer, alice, "Withdrawer should be Alice");
        assertEq(claimed, false, "Claimed should be false");
        assertEq(requestTimestamp, block.timestamp + CLAIM_DELAY, "Request timestamp should be updated");
        assertEq(amount, DEFAULT_AMOUNT, "Amount should be updated");
        assertEq(queued_, queued + DEFAULT_AMOUNT, "Queued should be updated");
    }
}
