// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {FuzzerFoundry} from "test/invariants/LidoARM/FuzzerFoundry.sol";

contract Unit is Test {
    FuzzerFoundry f;

    function setUp() public {
        f = new FuzzerFoundry();
        f.setUp();
    }

    function test_unit() public {
        // Use this template to replicate failing scenarios from invariant.
    }
}
