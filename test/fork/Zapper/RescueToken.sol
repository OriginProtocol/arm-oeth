// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {ZapperLidoARM} from "contracts/ZapperLidoARM.sol";

contract Fork_Concrete_ZapperLidoARM_RescueToken_Test_ is Fork_Shared_Test_ {
    function test_RevertWhen_RescueToken_CalledByNonOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only owner can call this function.");
        zapperLidoARM.rescueERC20(address(badToken), DEFAULT_AMOUNT);
    }

    function test_RescueToken() public {
        deal(address(weth), address(zapperLidoARM), DEFAULT_AMOUNT);
        assertEq(weth.balanceOf(address(zapperLidoARM)), DEFAULT_AMOUNT);
        assertEq(weth.balanceOf(address(this)), 0);

        // Rescue the tokens
        vm.prank(zapperLidoARM.owner());
        zapperLidoARM.rescueERC20(address(weth), DEFAULT_AMOUNT);

        // Check balance
        assertEq(weth.balanceOf(address(zapperLidoARM)), 0);
        assertEq(weth.balanceOf(address(this)), DEFAULT_AMOUNT);
    }
}
