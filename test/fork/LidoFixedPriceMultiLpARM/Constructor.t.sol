// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

contract Fork_Concrete_LidoFixedPriceMultiLpARM_Constructor_Test is Fork_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_Initial_State() public {
        assertEq(lidoARM.name(), "Lido ARM");
        assertEq(lidoARM.symbol(), "ARM-ST");
        assertEq(lidoARM.owner(), address(this));
        assertEq(lidoARM.operator(), operator);
        assertEq(lidoARM.feeCollector(), feeCollector);
        assertEq(lidoARM.fee(), 2000);
        assertEq(lidoARM.lastTotalAssets(), 1e12);
        assertEq(lidoARM.feesAccrued(), 0);
        // the 20% performance fee is removed on initialization
        assertEq(lidoARM.totalAssets(), 1e12);
        assertEq(lidoARM.totalSupply(), 1e12);
        assertEq(weth.balanceOf(address(lidoARM)), 1e12);
        assertEq(liquidityProviderController.totalAssetsCap(), 100 ether);
    }
}
