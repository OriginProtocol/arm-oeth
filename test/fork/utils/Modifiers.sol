// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Helpers} from "test/fork/utils/Helpers.sol";

abstract contract Modifiers is Helpers {
    /// @notice Impersonate the owner of the contract.
    modifier asOwner() {
        vm.startPrank(oethARM.owner());
        _;
        vm.stopPrank();
    }

    /// @notice Impersonate the governor of the vault.
    modifier asGovernor() {
        vm.startPrank(vault.governor());
        _;
        vm.stopPrank();
    }
}
