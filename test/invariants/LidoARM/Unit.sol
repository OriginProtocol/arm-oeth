// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {FuzzerFoundry_OethARM} from "test/invariants/LidoARM/FuzzerFoundry.sol";

contract Unit is Test {
    FuzzerFoundry_OethARM f;

    function setUp() public {
        f = new FuzzerFoundry_OethARM();
        f.setUp();
    }

    function test_unit() public {
        // Use this template to replicate failing scenarios from invariant.
    }
}
