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

    function test_ethena_replay_unit() public {
        //f.targetARMDeposit(309485009821345068724781054, 814939);
        //f.targetARMSetActiveMarket(true);
        //f.targetARMRequestRedeem(309485009821345068724781053, 52648352319298637938247915450656049947404);
        //f.targetMorphoTransferInRewards(0);
        //f._targetAfterAll();
        //assertTrue(f._propertyAfterAll(), "Property After All failed");
    }
}
