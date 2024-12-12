// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "lib/forge-std/src/Test.sol";
import {FuzzerFoundry} from "test/invariants/FuzzerFoundry.sol";

contract Unit is Test {
    FuzzerFoundry f;

    function setUp() public {
        f = new FuzzerFoundry();
        f.setUp();
    }

    function test_unit() public {
        // Initial deposit of 800_000 WETH from Dave
        f.handler_deposit(159, 800_000 ether);

        // Set fees to 0%
        f.handler_setFee(0);

        // Set price too:
        f.handler_setPrices(10100, 14000); // 999999999999999999999999999999985950 / 980000000000000000000000000000010100

        // Swap 500_000 WETH for 4_900_000 STETH from Eve
        f.handler_swapExactTokensForTokens(0, true, 500_000 ether);

        // New deposit of 600_000 WETH from Alice
        f.handler_deposit(252, 600_000 ether);

        // Check the fee accrued: 0
        uint256 feeAccruedBefore = f.handler_feeAccrued();

        // Set fees to 33%
        f.handler_setFee(3300);

        // Check the fee accrued: 3_300 WETH
        uint256 feeAccruedAfter = f.handler_feeAccrued();

        // This assertions is failing, which means that increasing fees generate fees!
        // Then if the owner claim fees, he will receive some fees, which should not happen.
        assertEq(feeAccruedBefore, feeAccruedAfter, "fee accrued before != fee accrued after");
    }
}
