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
    function test_Initial_State() public view {
        assertEq(lidoFixedPriceMulltiLpARM.name(), "Lido ARM");
        assertEq(lidoFixedPriceMulltiLpARM.symbol(), "ARM-ST");
        assertEq(lidoFixedPriceMulltiLpARM.owner(), address(this));
        assertEq(lidoFixedPriceMulltiLpARM.operator(), operator);
        assertEq(lidoFixedPriceMulltiLpARM.feeCollector(), feeCollector);
        assertEq(lidoFixedPriceMulltiLpARM.fee(), 2000);
        assertEq(lidoFixedPriceMulltiLpARM.lastTotalAssets(), 1e12);
        assertEq(lidoFixedPriceMulltiLpARM.feesAccrued(), 0);
        // the 20% performance fee is removed on initialization
        assertEq(lidoFixedPriceMulltiLpARM.totalAssets(), 1e12);
        assertEq(lidoFixedPriceMulltiLpARM.totalSupply(), 1e12);
        assertEq(weth.balanceOf(address(lidoFixedPriceMulltiLpARM)), 1e12);
        assertEq(liquidityProviderController.totalAssetsCap(), 100 ether);
    }
}
