// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

abstract contract Utils {
    function eq(uint256 a, uint256 b) internal pure returns (bool) {
        return a == b;
    }

    function gt(uint256 a, uint256 b) internal pure returns (bool) {
        return a > b;
    }

    function gte(uint256 a, uint256 b) internal pure returns (bool) {
        return a >= b;
    }

    function lt(uint256 a, uint256 b) internal pure returns (bool) {
        return a < b;
    }

    function lte(uint256 a, uint256 b) internal pure returns (bool) {
        return a <= b;
    }

    function approxEqAbs(uint256 a, uint256 b, uint256 epsilon) internal pure returns (bool) {
        return a > b ? a - b <= epsilon : b - a <= epsilon;
    }
}
