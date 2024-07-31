// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Utils
import {Mainnet} from "contracts/utils/Addresses.sol";

/// @notice The purpose of this contract is to test the `Ownable` contract.
contract Fork_Concrete_OethARM_Ownable_Test_ is Fork_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_SetOperator_Because_NotOwner() public {
        vm.expectRevert("ARM: Only owner can call this function.");
        vm.prank(alice);
        oethARM.setOperator(deployer);
    }

    function test_RevertWhen_SetOwner_Because_NotOwner() public {
        vm.expectRevert("ARM: Only owner can call this function.");
        vm.prank(alice);
        oethARM.setOwner(deployer);
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_SetOperator() public asOwner {
        // Assertions before
        assertEq(oethARM.operator(), address(0));

        oethARM.setOperator(operator);

        // Assertions after
        assertEq(oethARM.operator(), operator);
    }

    function test_SetOwner() public asOwner {
        // Assertions before
        assertEq(oethARM.owner(), Mainnet.TIMELOCK);

        oethARM.setOwner(alice);

        // Assertions after
        assertEq(oethARM.owner(), alice);
    }
}
