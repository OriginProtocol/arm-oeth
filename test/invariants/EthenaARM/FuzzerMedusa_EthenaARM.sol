// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Properties} from "./Properties.sol";

/// @title FuzzerMedusa_EthenaARM
/// @notice Concrete fuzzing contract implementing Medusa's invariant testing framework.
/// @dev    This contract configures and executes property-based testing:
///         - Inherits from Properties to access handler functions and properties
///         - All configuration is done in medusa.json.
contract FuzzerMedusa_EthenaARM is Properties {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    constructor() {
        _setup();
    }
}
