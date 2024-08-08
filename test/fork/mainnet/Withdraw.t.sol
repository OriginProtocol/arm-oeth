// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

/// @notice The purpose of this contract is to test the `requestWithdrawal`,
///         `claimWithdrawal` and `claimWithdrawals` functions in the `OEthARM` contract.
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
    function test_RequestWithdraw() public asOwner mockCallDripperCollect {
        (uint128 queuedBefore,,, uint128 nextWithdrawalIndex) = vault.withdrawalQueueMetadata();
        vm.expectEmit({emitter: address(oeth)});
        emit IERC20.Transfer(address(oethARM), address(0), 1 ether);
        (uint256 requestId, uint256 queued) = oethARM.requestWithdrawal(1 ether);

        // Assertions after
        assertEq(requestId, nextWithdrawalIndex, "Request ID");
        assertEq(queued, queuedBefore + 1 ether, "Queued amount should be 1 ether");
        assertEq(oeth.balanceOf(address(oethARM)), 9 ether, "OETH balance should be 99 ether");
    }

    function test_ClaimWithdraw_() public asOwner mockCallDripperCollect {
        // First request withdrawal
        (uint256 requestId,) = oethARM.requestWithdrawal(1 ether);

        // Add more liquidity to facilitate withdrawal
        (, uint128 claimable, uint128 claimed,) = vault.withdrawalQueueMetadata();
        deal(address(weth), address(vault), claimable - claimed + 1 ether);

        // Add liquidity to the withdrawal queue
        vault.addWithdrawalQueueLiquidity();

        // Skip delay
        skip(10 minutes);

        // Then claim withdrawal
        oethARM.claimWithdrawal(requestId);

        // Assertions after
        assertEq(weth.balanceOf(address(oethARM)), 1 ether, "WETH balance should be 1 ether");
    }

    function test_ClaimWithdraws() public asOwner mockCallDripperCollect {
        (,,, uint128 nextWithdrawalIndex) = vault.withdrawalQueueMetadata();

        // First request withdrawal
        oethARM.requestWithdrawal(1 ether);
        oethARM.requestWithdrawal(1 ether);

        // Add more liquidity to facilitate withdrawal
        (, uint128 claimable, uint128 claimed,) = vault.withdrawalQueueMetadata();
        deal(address(weth), address(vault), claimable - claimed + 1 ether);

        // Add liquidity to the withdrawal queue
        vault.addWithdrawalQueueLiquidity();

        // Skip delay
        skip(10 minutes);

        uint256[] memory requestIds = new uint256[](2);
        requestIds[0] = nextWithdrawalIndex;
        requestIds[1] = nextWithdrawalIndex + 1;
        // Then claim withdrawal
        oethARM.claimWithdrawals(requestIds);

        // Assertions after
        assertEq(weth.balanceOf(address(oethARM)), 2 ether, "WETH balance should be 1 ether");
    }
}
