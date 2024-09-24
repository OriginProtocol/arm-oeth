// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Base_Test_} from "test/Base.sol";

abstract contract Helpers is Base_Test_ {
    /// @notice Override `deal()` function to handle OETH and STETH special case.
    function deal(address token, address to, uint256 amount) internal override {
        // Handle OETH special case, as rebasing tokens are not supported by the VM.
        if (token == address(oeth)) {
            // Check than whale as enough OETH.
            require(oeth.balanceOf(oethWhale) >= amount, "Fork_Shared_Test_: Not enough OETH in WHALE_OETH");

            // Transfer OETH from WHALE_OETH to the user.
            vm.prank(oethWhale);
            oeth.transfer(to, amount);
        } else if (token == address(steth)) {
            // Check than whale as enough stETH. Whale is wsteth contract.
            require(steth.balanceOf(address(wsteth)) >= amount, "Fork_Shared_Test_: Not enough stETH in WHALE_stETH");

            if (amount == 0) {
                vm.startPrank(to);
                steth.transfer(address(0x1), steth.balanceOf(to));
                vm.stopPrank();
            } else {
                // Transfer stETH from WHALE_stETH to the user.
                vm.prank(address(wsteth));
                steth.transfer(to, amount);
            }
        } else {
            super.deal(token, to, amount);
        }
    }

    /// @notice Asserts the equality bewteen value of `withdrawalQueueMetadata()` and the expected values.
    function assertEqQueueMetadata(
        uint256 expectedQueued,
        uint256 expectedClaimable,
        uint256 expectedClaimed,
        uint256 expectedNextIndex
    ) public view {
        (uint256 queued, uint256 claimable, uint256 claimed, uint256 nextWithdrawalIndex) =
            lidoFixedPriceMulltiLpARM.withdrawalQueueMetadata();
        assertEq(queued, expectedQueued);
        assertEq(claimable, expectedClaimable);
        assertEq(claimed, expectedClaimed);
        assertEq(nextWithdrawalIndex, expectedNextIndex);
    }

    /// @notice Asserts the equality bewteen value of `withdrawalRequests()` and the expected values.
    function assertEqUserRequest(
        uint256 requestId,
        address withdrawer,
        bool claimed,
        uint256 claimTimestamp,
        uint256 assets,
        uint256 queued
    ) public view {
        (address _withdrawer, bool _claimed, uint40 _claimTimestamp, uint128 _assets, uint128 _queued) =
            lidoFixedPriceMulltiLpARM.withdrawalRequests(requestId);
        assertEq(_withdrawer, withdrawer, "Wrong withdrawer");
        assertEq(_claimed, claimed, "Wrong claimed");
        assertEq(_claimTimestamp, claimTimestamp, "Wrong claimTimestamp");
        assertEq(_assets, assets, "Wrong assets");
        assertEq(_queued, queued, "Wrong queued");
    }
}
