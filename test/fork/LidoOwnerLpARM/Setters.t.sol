// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

contract Fork_Concrete_LidoOwnerLpARM_Setters_Test_ is Fork_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_SetPrices_Because_PriceCross() public {
        vm.expectRevert("ARM: Price cross");
        lidoOwnerLpARM.setPrices(90 * 1e33, 89 * 1e33);

        vm.expectRevert("ARM: Price cross");
        lidoOwnerLpARM.setPrices(72, 70);

        vm.expectRevert("ARM: Price cross");
        lidoOwnerLpARM.setPrices(1005 * 1e33, 1000 * 1e33);

        // Both set to 1.0
        vm.expectRevert("ARM: Price cross");
        lidoOwnerLpARM.setPrices(1e36, 1e36);
    }

    function test_RevertWhen_SetPrices_Because_PriceRange() public asLidoOwnerLpARMOperator {
        // buy price 11 basis points higher than 1.0
        vm.expectRevert("ARM: buy price too high");
        lidoOwnerLpARM.setPrices(10011e32, 10020e32);

        // sell price 11 basis points lower than 1.0
        vm.expectRevert("ARM: sell price too low");
        lidoOwnerLpARM.setPrices(9980e32, 9989e32);

        // Forgot to scale up to 36 decimals
        vm.expectRevert("ARM: sell price too low");
        lidoOwnerLpARM.setPrices(1e18, 1e18);
    }

    function test_RevertWhen_SetPrices_Because_NotOwnerOrOperator() public asRandomAddress {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        lidoOwnerLpARM.setPrices(0, 0);
    }

    function test_RevertWhen_SetOwner_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoOwnerLpARM.setOwner(address(0));
    }

    function test_RevertWhen_SetOperator_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoOwnerLpARM.setOperator(address(0));
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_SetPrices_Operator() public asLidoOwnerLpARMOperator {
        // buy price 10 basis points higher than 1.0
        lidoOwnerLpARM.setPrices(1001e33, 1002e33);
        // sell price 10 basis points lower than 1.0
        lidoOwnerLpARM.setPrices(9980e32, 9991e32);
        // 2% of one basis point spread
        lidoOwnerLpARM.setPrices(999999e30, 1000001e30);

        lidoOwnerLpARM.setPrices(992 * 1e33, 1001 * 1e33);
        lidoOwnerLpARM.setPrices(1001 * 1e33, 1004 * 1e33);
        lidoOwnerLpARM.setPrices(992 * 1e33, 2000 * 1e33);

        // Check the traderates
        assertEq(lidoOwnerLpARM.traderate0(), 500 * 1e33);
        assertEq(lidoOwnerLpARM.traderate1(), 992 * 1e33);
    }

    function test_SetPrices_Owner() public {
        // buy price 11 basis points higher than 1.0
        lidoOwnerLpARM.setPrices(10011e32, 10020e32);

        // sell price 11 basis points lower than 1.0
        lidoOwnerLpARM.setPrices(9980e32, 9989e32);
    }

    function test_SetOperator() public asLidoOwnerLpARMOwner {
        lidoOwnerLpARM.setOperator(address(this));
        assertEq(lidoOwnerLpARM.operator(), address(this));
    }
}
