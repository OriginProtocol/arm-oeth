// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Fork_Shared_Test} from "test/fork/OriginARM/shared/Shared.sol";

contract Fork_Concrete_OriginARM_Allocate_Test_ is Fork_Shared_Test {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_Allocate() public setARMBuffer(0) addMarket(address(market)) setActiveMarket(address(market)) {}
}
