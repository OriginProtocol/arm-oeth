// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20, IStETHWithdrawal} from "contracts/Interfaces.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

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
        uint256[] memory emptyList = new uint256[](0);

        // Expected events
        vm.expectEmit({emitter: address(lidoARM)});
        emit LidoARM.RequestLidoWithdrawals(emptyList, emptyList);

        uint256[] memory requestIds = lidoARM.requestLidoWithdrawals(emptyList);

        assertEq(requestIds, emptyList);
    }

    function test_RequestLidoWithdrawals_SingleAmount_1ether() public asOperator {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = DEFAULT_AMOUNT;
        uint256[] memory expectedLidoRequestIds = new uint256[](1);
        expectedLidoRequestIds[0] = IStETHWithdrawal(Mainnet.LIDO_WITHDRAWAL).getLastRequestId() + 1;

        // Expected events
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(address(lidoARM), address(lidoARM.lidoWithdrawalQueue()), amounts[0]);
        vm.expectEmit({emitter: address(lidoARM)});
        emit LidoARM.RequestLidoWithdrawals(amounts, expectedLidoRequestIds);

        // Main call
        uint256[] memory requestIds = lidoARM.requestLidoWithdrawals(amounts);

        assertEq(requestIds, expectedLidoRequestIds);
    }

    function test_RequestLidoWithdrawals_SingleAmount_1000ethers() public asOperator {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1_000 ether;
        uint256[] memory expectedLidoRequestIds = new uint256[](1);
        expectedLidoRequestIds[0] = IStETHWithdrawal(Mainnet.LIDO_WITHDRAWAL).getLastRequestId() + 1;

        // Expected events
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(address(lidoARM), address(lidoARM.lidoWithdrawalQueue()), amounts[0]);
        vm.expectEmit({emitter: address(lidoARM)});
        emit LidoARM.RequestLidoWithdrawals(amounts, expectedLidoRequestIds);

        // Main call
        uint256[] memory requestIds = lidoARM.requestLidoWithdrawals(amounts);

        assertEq(requestIds, expectedLidoRequestIds);
    }

    function test_RequestLidoWithdrawals_MultipleAmount() public asOperator {
        uint256 length = _bound(vm.randomUint(), 2, 10);
        uint256[] memory amounts = new uint256[](length);
        uint256[] memory expectedLidoRequestIds = new uint256[](length);
        uint256 startingLidoRequestId = IStETHWithdrawal(Mainnet.LIDO_WITHDRAWAL).getLastRequestId() + 1;
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = _bound(vm.randomUint(), 0, 1_000 ether);
            expectedLidoRequestIds[i] = startingLidoRequestId + i;
        }

        vm.expectEmit({emitter: address(lidoARM)});
        emit LidoARM.RequestLidoWithdrawals(amounts, expectedLidoRequestIds);

        // Main call
        uint256[] memory requestIds = lidoARM.requestLidoWithdrawals(amounts);

        assertEq(requestIds, expectedLidoRequestIds);
    }
}
