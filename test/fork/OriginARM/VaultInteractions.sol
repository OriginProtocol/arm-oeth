// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {OriginARM} from "contracts/OriginARM.sol";
import {Fork_Shared_Test} from "test/fork/OriginARM/shared/Shared.sol";

contract Fork_Concrete_OriginARM_VaultInteractions_Test_ is Fork_Shared_Test {
    function test_RevertWhen_RequestingOriginWithdrawal_IfNotOperator() public asNotOperatorNorGovernor {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        originARM.requestOriginWithdrawal(DEFAULT_AMOUNT);
    }

    function test_RequestOriginWithdrawal() public asGovernor {
        assertEq(originARM.vaultWithdrawalAmount(), 0, "Initial vault withdrawal amount should be 0");

        deal(address(os), address(originARM), DEFAULT_AMOUNT);

        vm.expectEmit(address(originARM));
        emit OriginARM.RequestOriginWithdrawal(DEFAULT_AMOUNT, 1);

        originARM.requestOriginWithdrawal(DEFAULT_AMOUNT);

        assertEq(originARM.vaultWithdrawalAmount(), DEFAULT_AMOUNT, "Vault withdrawal amount should be updated");
    }

    function test_ClaimOriginWithdrawals() public asGovernor {
        // Deal OS to the ARM contract and the vault
        deal(address(os), address(originARM), DEFAULT_AMOUNT);
        deal(address(ws), address(vault), DEFAULT_AMOUNT);

        // Request an Origin withdrawal
        uint256 requestId = originARM.requestOriginWithdrawal(DEFAULT_AMOUNT);

        // Build the request IDs array
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;

        // Expected event
        vm.expectEmit(address(originARM));
        emit OriginARM.ClaimOriginWithdrawals(requestIds, DEFAULT_AMOUNT);

        // Main call
        originARM.claimOriginWithdrawals(requestIds);

        // Check the vault withdrawal amount
        assertEq(originARM.vaultWithdrawalAmount(), 0, "Vault withdrawal amount should be updated");
    }
}
