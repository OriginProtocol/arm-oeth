// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

library MathComparisons {
    function eq(uint256 a, uint256 b) public pure returns (bool) {
        return a == b;
    }

    function gt(uint256 a, uint256 b) public pure returns (bool) {
        return a > b;
    }

    function gte(uint256 a, uint256 b) public pure returns (bool) {
        return a >= b;
    }

    function lt(uint256 a, uint256 b) public pure returns (bool) {
        return a < b;
    }

    function lte(uint256 a, uint256 b) public pure returns (bool) {
        return a <= b;
    }

    function eqApproxAbs(uint256 a, uint256 b, uint256 epsilon) public pure returns (bool) {
        return a > b ? a - b <= epsilon : b - a <= epsilon;
    }

    function eqApproxRel(uint256 a, uint256 b, uint256 epsilon) public pure returns (bool) {
        return a > b ? (a - b) * 1e18 / a <= epsilon : (b - a) * 1e18 / b <= epsilon;
    }

    function gteApproxAbs(uint256 a, uint256 b, uint256 epsilon) public pure returns (bool) {
        return a >= b ? true : (b - a <= epsilon);
    }

    function gteApproxRel(uint256 a, uint256 b, uint256 epsilon) public pure returns (bool) {
        return a >= b ? true : (b - a <= (b * epsilon) / 1e18);
    }
}
