// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Properties} from "./Properties.t.sol";

/// @title FuzzerFoundry_LidoARM
/// @notice Concrete fuzzing contract implementing Foundry's invariant testing framework.
/// @dev    This contract configures and executes property-based testing:
///         - Inherits from Properties to access handler functions and properties
///         - Configures fuzzer targeting (contracts, selectors, senders)
///         - Implements invariant test functions that call property validators
///         - Each invariant function represents a critical system property to maintain
///         - Fuzzer will call targeted handlers randomly and check invariants after each call
contract FuzzerFoundry_LidoARM_New is Properties {
    constructor() {
        consoleLogs = true;
        foundryFuzzer = true;
    }

    function setUp() public virtual override {
        // --- Common setup ---
        super.setUp();

        // --- Setup Fuzzer target ---
        // Setup target
        targetContract(address(this));

        // Add selectors
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = this.targetDeposit.selector;
        selectors[1] = this.targetRequestRedeem.selector;
        selectors[2] = this.targetClaimRedeem.selector;

        // Target selectors
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    function invariantSwap() public view {
        // Example invariant test function
    }
}
