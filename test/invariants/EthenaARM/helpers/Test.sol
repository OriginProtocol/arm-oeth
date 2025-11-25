// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

import {FuzzerFoundry_EthenaARM} from "test/invariants/EthenaARM/FuzzerFoundry_EthenaARM.sol";

contract Unit_Ethena_replay is Test {
    FuzzerFoundry_EthenaARM f;

    function setUp() public {
        f = new FuzzerFoundry_EthenaARM();
        f.setUp();
    }

    function test_unit() public {
        //f.targetARMDeposit(309485009.821_345_068_724_781_052 ether, 1);
        //f.targetARMDeposit(3538, 10000);
        //f.targetARMSetActiveMarket(true); // usde: 309485009821346068724784590
        //f.targetARMRequestRedeem(309485009.821_345_068_724_781_054 ether, 6731);
        //f.targetMorphoTransferInRewards(7);
        //f.targetAfterAll(); //
        //assertTrue(f.propertyAfterAll());
    }
}
