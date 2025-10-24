// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {FuzzerFoundry_LidoARM} from "test/invariants/LidoARM/FuzzerFoundry.sol";

contract Unit is Test {
    FuzzerFoundry_LidoARM f;

    function setUp() public {
        f = new FuzzerFoundry_LidoARM();
        f.setUp();
    }

    function test_unit() public {
        // Use this template to replicate failing scenarios from invariant.
    }
}
