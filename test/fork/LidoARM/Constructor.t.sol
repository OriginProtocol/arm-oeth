// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Mainnet} from "src/contracts/utils/Addresses.sol";
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
        assertEq(lidoARM.name(), "Lido ARM");
        assertEq(lidoARM.symbol(), "ARM-ST");
        assertEq(lidoARM.owner(), address(this));
        assertEq(lidoARM.operator(), operator);
        assertEq(lidoARM.feeCollector(), feeCollector);
        assertEq(lidoARM.fee(), 2000);
        assertEq(int256(lidoARM.totalAssets()), int256(MIN_TOTAL_SUPPLY));
        assertEq(lidoARM.feesAccrued(), 0);
        // the 20% performance fee is removed on initialization
        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY);
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY);
        assertEq(capManager.totalAssetsCap(), 100 ether);
    }
}
