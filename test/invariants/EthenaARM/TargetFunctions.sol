// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Setup} from "./Setup.sol";

/// @title TargetFunctions
/// @notice TargetFunctions contract for tests, containing the target functions that should be tested.
///         This is the entry point with the contract we are testing. Ideally, it should never revert.
abstract contract TargetFunctions is Setup {}
