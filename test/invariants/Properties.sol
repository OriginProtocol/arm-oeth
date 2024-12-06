// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Setup} from "./Setup.sol";

abstract contract Properties is Setup {
    function property_swap_A() public view returns (bool) {
        return true;
    }
}
