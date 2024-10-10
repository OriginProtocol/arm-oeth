// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";

contract Fork_Concrete_LidoARM_RequestLidoWithdrawals_Test_ is Fork_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        deal(address(steth), address(lidoARM), 10_000 ether);
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_RequestLidoWithdrawals_NotOperator() public asRandomAddress {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        lidoARM.requestLidoWithdrawals(new uint256[](0));
    }

    function test_RevertWhen_RequestLidoWithdrawals_Because_BalanceExceeded() public asOperator {
        // Remove all stETH from the contract
        deal(address(steth), address(lidoARM), 0);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = DEFAULT_AMOUNT;

        vm.expectRevert("BALANCE_EXCEEDED");
        lidoARM.requestLidoWithdrawals(amounts);
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_RequestLidoWithdrawals_EmptyList() public asOperator {
        uint256[] memory requestIds = lidoARM.requestLidoWithdrawals(new uint256[](0));
        assertEq(requestIds.length, 0);
    }

    function test_RequestLidoWithdrawals_SingleAmount_1ether() public asOperator {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = DEFAULT_AMOUNT;

        // Expected events
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(address(lidoARM), address(lidoARM.withdrawalQueue()), amounts[0]);

        // Main call
        uint256[] memory requestIds = lidoARM.requestLidoWithdrawals(amounts);

        assertEq(requestIds.length, 1);
        assertGt(requestIds[0], 0);
    }

    function test_RequestLidoWithdrawals_SingleAmount_1000ethers() public asOperator {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1_000 ether;

        // Expected events
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(address(lidoARM), address(lidoARM.withdrawalQueue()), amounts[0]);

        // Main call
        uint256[] memory requestIds = lidoARM.requestLidoWithdrawals(amounts);

        assertEq(requestIds.length, 1);
        assertGt(requestIds[0], 0);
    }

    function test_RequestLidoWithdrawals_MultipleAmount() public asOperator {
        uint256 length = _bound(vm.randomUint(), 2, 10);
        uint256[] memory amounts = new uint256[](length);
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = _bound(vm.randomUint(), 0, 1_000 ether);
        }

        // Main call
        uint256[] memory requestIds = lidoARM.requestLidoWithdrawals(amounts);

        uint256 initialRequestId = requestIds[0];
        assertGt(initialRequestId, 0);
        for (uint256 i = 1; i < amounts.length; i++) {
            assertEq(requestIds[i], initialRequestId + i);
        }
    }
}
