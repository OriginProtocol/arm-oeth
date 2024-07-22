// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

/// @notice The puprose of this contract is to test the `transferToken` and `transferEth` functions in the `OEthARM` contract.
contract Fork_Concrete_OethARM_Transfer_Test_ is Fork_Shared_Test_ {
    bool public shoudRevertOnReceive;

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

    function test_RevertWhen_TransferETH_Because_NotOwner() public {
        vm.expectRevert("ARM: Only owner can call this function.");
        oethARM.transferEth(address(0), 0);
    }

    function test_RevertWhen_TransferETH_Because_ETHTransferFailed() public asOwner {
        shoudRevertOnReceive = true;

        vm.expectRevert("ARM: ETH transfer failed");
        oethARM.transferEth(address(this), 10 ether);
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

    function test_TransferETH() public asOwner {
        // Assertions before
        uint256 balanceBefore = address(this).balance;
        assertEq(address(oethARM).balance, 100 ether);

        oethARM.transferEth(address(this), 10 ether);

        // Assertions after
        assertEq(address(this).balance - balanceBefore, 10 ether);
        assertEq(address(oethARM).balance, 90 ether);
    }

    //////////////////////////////////////////////////////
    /// --- RECEIVE
    //////////////////////////////////////////////////////
    receive() external payable {
        if (shoudRevertOnReceive) revert();
    }
}
