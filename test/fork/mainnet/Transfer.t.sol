// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

/// @notice The purpose of this contract is to test the `transferToken` and `transferEth` functions in the `OethARM` contract.
contract Fork_Concrete_OethARM_Transfer_Test_ is Fork_Shared_Test_ {
    bool public shouldRevertOnReceive;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////

    function setUp() public override {
        super.setUp();

        // Deal tokens
        deal(address(oethARM), 100 ether);
        deal(address(weth), address(oethARM), 100 ether);
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_TransferToken_Because_NotOwner() public {
        vm.expectRevert("ARM: Only owner can call this function.");
        oethARM.transferToken(address(0), address(0), 0);
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_TransferToken() public asOwner {
        // Assertions before
        assertEq(weth.balanceOf(address(this)), 0);
        assertEq(weth.balanceOf(address(oethARM)), 100 ether);

        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(oethARM), address(this), 10 ether);
        oethARM.transferToken(address(weth), address(this), 10 ether);

        // Assertions after
        assertEq(weth.balanceOf(address(this)), 10 ether);
        assertEq(weth.balanceOf(address(oethARM)), 90 ether);
    }

    //////////////////////////////////////////////////////
    /// --- RECEIVE
    //////////////////////////////////////////////////////
    receive() external payable {
        if (shouldRevertOnReceive) revert();
    }
}
