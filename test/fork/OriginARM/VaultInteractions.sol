// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Fork_Shared_Test} from "test/fork/OriginARM/shared/Shared.sol";

contract Fork_Concrete_OriginARM_VaultInteractions_Test_ is Fork_Shared_Test {
    function test_RevertWhen_RequestingOriginWithdrawal_IfNotOperator() public asNotOperatorNorGovernor {
        vm.expectRevert(bytes4(keccak256("OnlyOperatorOrOwner()")));
        originARM.requestBaseAssetRedeem(address(os), DEFAULT_AMOUNT);
    }

    function test_RequestOriginWithdrawal() public asGovernor {
        assertEq(originARM.vaultWithdrawalAmount(), 0, "Initial vault withdrawal amount should be 0");

        deal(address(os), address(originARM), DEFAULT_AMOUNT);

        originARM.requestBaseAssetRedeem(address(os), DEFAULT_AMOUNT);

        (,,,,, uint120 pendingRedeemAssets,,) = originARM.baseAssetConfigs(address(os));
        assertEq(pendingRedeemAssets, DEFAULT_AMOUNT, "Pending redeem assets should be updated");
    }

    function test_ClaimOriginWithdrawals() public asGovernor {
        // Deal OS to the ARM contract and the vault
        deal(address(os), address(originARM), DEFAULT_AMOUNT);
        deal(address(ws), address(vault), DEFAULT_AMOUNT);

        // Request an Origin withdrawal
        originARM.requestBaseAssetRedeem(address(os), DEFAULT_AMOUNT);
        assertEq(originAssetAdapter.pendingRequestId(0), 1, "pending request id");

        // Main call
        originARM.claimBaseAssetRedeem(address(os), DEFAULT_AMOUNT);

        // Check the vault withdrawal amount
        assertEq(originARM.vaultWithdrawalAmount(), 0, "Vault withdrawal amount should be updated");
    }
}
