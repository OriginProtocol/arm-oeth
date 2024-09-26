// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

contract Fork_Concrete_LidoARM_Constructor_Test is Fork_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_Initial_State() public view {
        assertEq(lidoFixedPriceMultiLpARM.name(), "Lido ARM");
        assertEq(lidoFixedPriceMultiLpARM.symbol(), "ARM-ST");
        assertEq(lidoFixedPriceMultiLpARM.owner(), address(this));
        assertEq(lidoFixedPriceMultiLpARM.operator(), operator);
        assertEq(lidoFixedPriceMultiLpARM.feeCollector(), feeCollector);
        assertEq(lidoFixedPriceMultiLpARM.fee(), 2000);
        assertEq(lidoFixedPriceMultiLpARM.lastTotalAssets(), 1e12);
        assertEq(lidoFixedPriceMultiLpARM.feesAccrued(), 0);
        // the 20% performance fee is removed on initialization
        assertEq(lidoFixedPriceMultiLpARM.totalAssets(), 1e12);
        assertEq(lidoFixedPriceMultiLpARM.totalSupply(), 1e12);
        assertEq(weth.balanceOf(address(lidoFixedPriceMultiLpARM)), 1e12);
        assertEq(liquidityProviderController.totalAssetsCap(), 100 ether);
    }
}
