// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Properties} from "./Properties.sol";

/// @title FuzzerFoundry
/// @notice Concrete fuzzing contract implementing Foundry's invariant testing framework.
/// @dev    This contract configures and executes property-based testing:
///         - Inherits from Properties to access handler functions and properties
///         - Configures fuzzer targeting (contracts, selectors, senders)
///         - Implements invariant test functions that call property validators
///         - Each invariant function represents a critical system property to maintain
///         - Fuzzer will call targeted handlers randomly and check invariants after each call
contract FuzzerFoundry_EthenaARM is Properties {
    bool public constant override isLabelAvailable = true;

    function test() public {}
}
