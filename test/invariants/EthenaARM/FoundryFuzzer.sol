// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Properties} from "./Properties.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

/// @title FuzzerFoundry
/// @notice Concrete fuzzing contract implementing Foundry's invariant testing framework.
/// @dev    This contract configures and executes property-based testing:
///         - Inherits from Properties to access handler functions and properties
///         - Configures fuzzer targeting (contracts, selectors, senders)
///         - Implements invariant test functions that call property validators
///         - Each invariant function represents a critical system property to maintain
///         - Fuzzer will call targeted handlers randomly and check invariants after each call
contract FuzzerFoundry_EthenaARM is Properties, StdInvariant {
    bool public constant override isLabelAvailable = true;
    bool public constant override isAssumeAvailable = true;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        // --- Setup Fuzzer target ---
        // Setup target
        targetContract(address(this));

        // Add selectors
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = this.targetSUSDeDeposit.selector;
        selectors[1] = this.targetSUSDeCooldownShares.selector;
        selectors[2] = this.targetSUSDeUnstake.selector;
        selectors[3] = this.targetSUSDeTransferInRewards.selector;

        // Target selectors
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    //////////////////////////////////////////////////////
    /// --- INVARIANTS
    //////////////////////////////////////////////////////
    function invariantA() public {}
}
