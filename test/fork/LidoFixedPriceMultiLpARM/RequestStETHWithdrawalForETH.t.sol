// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";

contract Fork_Concrete_LidoARM_RequestStETHWithdrawalForETH_Test_ is Fork_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        deal(address(steth), address(lidoFixedPriceMultiLpARM), 10_000 ether);
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_RequestStETHWithdrawalForETH_NotOperator() public asRandomAddress {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        lidoFixedPriceMultiLpARM.requestStETHWithdrawalForETH(new uint256[](0));
    }

    function test_RevertWhen_RequestStETHWithdrawalForETH_Because_BalanceExceeded()
        public
        asLidoFixedPriceMulltiLpARMOperator
        approveStETHOnLidoARM
    {
        // Remove all stETH from the contract
        deal(address(steth), address(lidoFixedPriceMultiLpARM), 0);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = DEFAULT_AMOUNT;

        vm.expectRevert("BALANCE_EXCEEDED");
        lidoFixedPriceMultiLpARM.requestStETHWithdrawalForETH(amounts);
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_RequestStETHWithdrawalForETH_EmptyList() public asLidoFixedPriceMulltiLpARMOperator {
        uint256[] memory requestIds = lidoFixedPriceMultiLpARM.requestStETHWithdrawalForETH(new uint256[](0));
        assertEq(requestIds.length, 0);
    }

    function test_RequestStETHWithdrawalForETH_SingleAmount_1ether()
        public
        asLidoFixedPriceMulltiLpARMOperator
        approveStETHOnLidoARM
    {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = DEFAULT_AMOUNT;

        // Expected events
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(
            address(lidoFixedPriceMultiLpARM), address(lidoFixedPriceMultiLpARM.withdrawalQueue()), amounts[0]
        );

        // Main call
        uint256[] memory requestIds = lidoFixedPriceMultiLpARM.requestStETHWithdrawalForETH(amounts);

        assertEq(requestIds.length, 1);
        assertGt(requestIds[0], 0);
    }

    function test_RequestStETHWithdrawalForETH_SingleAmount_1000ethers()
        public
        asLidoFixedPriceMulltiLpARMOperator
        approveStETHOnLidoARM
    {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1_000 ether;

        // Expected events
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(
            address(lidoFixedPriceMultiLpARM), address(lidoFixedPriceMultiLpARM.withdrawalQueue()), amounts[0]
        );

        // Main call
        uint256[] memory requestIds = lidoFixedPriceMultiLpARM.requestStETHWithdrawalForETH(amounts);

        assertEq(requestIds.length, 1);
        assertGt(requestIds[0], 0);
    }

    function test_RequestStETHWithdrawalForETH_MultipleAmount()
        public
        asLidoFixedPriceMulltiLpARMOperator
        approveStETHOnLidoARM
    {
        uint256 length = _bound(vm.randomUint(), 2, 10);
        uint256[] memory amounts = new uint256[](length);
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = _bound(vm.randomUint(), 0, 1_000 ether);
        }

        // Main call
        uint256[] memory requestIds = lidoFixedPriceMultiLpARM.requestStETHWithdrawalForETH(amounts);

        uint256 initialRequestId = requestIds[0];
        assertGt(initialRequestId, 0);
        for (uint256 i = 1; i < amounts.length; i++) {
            assertEq(requestIds[i], initialRequestId + i);
        }
    }
}
