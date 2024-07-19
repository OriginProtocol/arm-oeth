// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

contract Fork_Concrete_OethARM_Withdraw_Test_ is Fork_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        // Deal tokens
        deal(address(oeth), address(oethARM), 10 ether);
        deal(address(weth), address(vault), 10 ether);

        // Remove solvency check
        vm.prank(vault.governor());
        vault.setMaxSupplyDiff(0);

        // Bypass call to the dripper
        vm.mockCall({callee: vault.dripper(), data: abi.encodeWithSignature("collect()"), returnData: abi.encode(true)});
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_RequestWithdraw() public {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        oethARM.requestWithdrawal(1 ether);
    }

    function test_RevertWhen_ClaimWithdraw() public {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        oethARM.claimWithdrawal(0);
    }

    function test_RevertWhen_ClaimWithdraws() public {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        oethARM.claimWithdrawals(new uint256[](0));
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_RequestWithdraw() public {
        vm.prank(oethARM.owner());
        vm.expectEmit({emitter: address(oeth)});
        emit IERC20.Transfer(address(oethARM), address(0), 1 ether);
        (uint256 requestId, uint256 queued) = oethARM.requestWithdrawal(1 ether);

        // Assertions after
        assertEq(requestId, 0, "Request ID should be 0");
        assertEq(queued, 1 ether, "Queued amount should be 1 ether");
        assertEq(oeth.balanceOf(address(oethARM)), 9 ether, "OETH balance should be 99 ether");
    }

    function test_ClaimWithdraw_() public {
        // First request withdrawal
        vm.prank(oethARM.owner());
        (uint256 requestId,) = oethARM.requestWithdrawal(1 ether);

        vault.addWithdrawalQueueLiquidity();
        skip(10 minutes); // Todo: fetch direct value from contract

        // Then claim withdrawal
        vm.prank(oethARM.owner());
        oethARM.claimWithdrawal(requestId);

        // Assertions after
        assertEq(weth.balanceOf(address(oethARM)), 1 ether, "WETH balance should be 1 ether");
    }

    function test_ClaimWithdraws() public {
        // First request withdrawal
        vm.startPrank(oethARM.owner());
        oethARM.requestWithdrawal(1 ether);
        oethARM.requestWithdrawal(1 ether);
        vm.stopPrank();

        vault.addWithdrawalQueueLiquidity();
        skip(10 minutes); // Todo: fetch direct value from contract

        uint256[] memory requestIds = new uint256[](2);
        requestIds[0] = 0;
        requestIds[1] = 1;
        // Then claim withdrawal
        vm.prank(oethARM.owner());
        oethARM.claimWithdrawals(requestIds);

        // Assertions after
        assertEq(weth.balanceOf(address(oethARM)), 2 ether, "WETH balance should be 1 ether");
    }
}
