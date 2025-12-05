// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

library Math {
    //////////////////////////////////////////////////////
    /// --- ABS
    //////////////////////////////////////////////////////
    /// @notice Returns the absolute value of an int256 as uint256
    /// @param a The integer to get the absolute value of
    /// @return The absolute value as uint256
    function abs(int256 a) internal pure returns (uint256) {
        return uint256(a >= 0 ? a : -a);
    }

    /// @notice Returns the absolute difference between two uint256 values
    /// @param a The first value
    /// @param b The second value
    /// @return The absolute difference
    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a - b : b - a;
    }

    //////////////////////////////////////////////////////
    /// --- MIN & MAX
    //////////////////////////////////////////////////////
    /// @notice Returns the maximum of two uint256 values
    /// @param a The first value
    /// @param b The second value
    /// @return The maximum value
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    /// @notice Returns the minimum of two uint256 values
    /// @param a The first value
    /// @param b The second value
    /// @return The minimum value
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }

    //////////////////////////////////////////////////////
    /// --- EQUALITY STRICT AND APPROXIMATE
    //////////////////////////////////////////////////////
    /// @notice Checks if two uint256 values are equal
    /// @param a The first value
    /// @param b The second value
    /// @return True if equal, false otherwise
    function eq(uint256 a, uint256 b) internal pure returns (bool) {
        return a == b;
    }

    /// @notice Checks if two uint256 values are approximately equal within a maximum absolute difference
    /// @param a The first value
    /// @param b The second value
    /// @param maxDelta The maximum allowed absolute difference
    /// @return True if approximately equal, false otherwise
    function approxEqAbs(uint256 a, uint256 b, uint256 maxDelta) internal pure returns (bool) {
        if (a >= b) {
            return (a - b) <= maxDelta;
        } else {
            return (b - a) <= maxDelta;
        }
    }

    /// @notice Checks if two uint256 values are approximately equal within a maximum relative difference (in WAD)
    /// @param a The first value
    /// @param b The second value
    /// @param maxRelDeltaWAD The maximum allowed relative difference in WAD (1e18 = 100%)
    /// @return True if approximately equal, false otherwise
    function approxEqRel(uint256 a, uint256 b, uint256 maxRelDeltaWAD) internal pure returns (bool) {
        if (a == b) {
            return true;
        }
        uint256 _absDiff = a >= b ? a - b : b - a;
        uint256 relDiffWAD = (_absDiff * 1 ether) / Math.max(a, b);
        return relDiffWAD <= maxRelDeltaWAD;
    }

    //////////////////////////////////////////////////////
    /// --- GREATER THAN
    //////////////////////////////////////////////////////
    /// @notice Checks if a is greater than b
    /// @param a The first value
    /// @param b The second value
    /// @return True if a > b, false otherwise
    function gt(uint256 a, uint256 b) internal pure returns (bool) {
        return a > b;
    }

    /// @notice Checks if a is greater than or equal to b
    function gte(uint256 a, uint256 b) internal pure returns (bool) {
        return a >= b;
    }

    /// @notice Checks if a is approximately greater than or equal to b within a maximum absolute difference
    /// @param a The first value
    /// @param b The second value
    /// @param maxDelta The maximum allowed absolute difference
    /// @return True if a is approximately greater than or equal to b, false otherwise
    function approxGteAbs(uint256 a, uint256 b, uint256 maxDelta) internal pure returns (bool) {
        if (a >= b) {
            return true;
        } else {
            return (b - a) <= maxDelta;
        }
    }

    //////////////////////////////////////////////////////
    /// --- LESS THAN
    //////////////////////////////////////////////////////
    /// @notice Checks if a is less than b
    /// @param a The first value
    /// @param b The second value
    /// @return True if a < b, false otherwise
    function lt(uint256 a, uint256 b) internal pure returns (bool) {
        return a < b;
    }

    /// @notice Checks if a is less than or equal to b
    /// @param a The first value
    /// @param b The second value
    /// @return True if a <= b, false otherwise
    function lte(uint256 a, uint256 b) internal pure returns (bool) {
        return a <= b;
    }
}
