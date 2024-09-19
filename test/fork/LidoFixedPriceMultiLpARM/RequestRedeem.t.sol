// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

contract Fork_Concrete_LidoFixedPriceMultiLpARM_RequestRedeem_Test_ is Fork_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_RequestRedeem_SimpleCase()
        public
        asLidoFixedPriceMultiLpARMOwner
        setLiquidityProviderCap(address(this), 20 ether)
    {
        deal(address(weth), address(this), 10 ether);

        lidoARM.deposit(10 ether);
        lidoARM.requestRedeem(8 ether);
    }
}
