// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {TargetFunctions} from "./TargetFunctions.sol";

/// @title Properties
/// @notice Abstract contract defining invariant properties for formal verification and fuzzing.
/// @dev    This contract contains pure property functions that express system invariants:
///         - Properties must be implemented as view/pure functions returning bool
///         - Each property should represent a mathematical invariant of the system
///         - Properties should be stateless and deterministic
///         - Property names should clearly indicate what invariant they check
///         Usage: Properties are called by fuzzing contracts to validate system state
abstract contract Properties is TargetFunctions {}
