// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20, IStETHWithdrawal} from "contracts/Interfaces.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

contract Fork_Concrete_LidoARM_RequestLidoWithdrawals_Test_ is Fork_Shared_Test_ {
    uint256[] amounts0;
    uint256[] amounts1;
    uint256[] amounts2;

    IStETHWithdrawal public stETHWithdrawal = IStETHWithdrawal(Mainnet.LIDO_WITHDRAWAL);
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////

    function setUp() public override {
        super.setUp();

        deal(address(steth), address(lidoARM), 10_000 ether);

        amounts0 = new uint256[](0);

        amounts1 = new uint256[](1);
        amounts1[0] = DEFAULT_AMOUNT;

        amounts2 = new uint256[](2);
        amounts2[0] = DEFAULT_AMOUNT;
        amounts2[1] = DEFAULT_AMOUNT;
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_ClaimLidoWithdrawals_EmptyList() public asOperator requestLidoWithdrawalsOnLidoARM(new uint256[](0)) {
        assertEq(address(lidoARM).balance, 0);
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0);

        uint256[] memory emptyList = new uint256[](0);

        // Expected events
        vm.expectEmit({emitter: address(lidoARM)});
        emit LidoARM.ClaimLidoWithdrawals(emptyList);

        // Main call
        lidoARM.claimLidoWithdrawals(emptyList, emptyList);

        assertEq(address(lidoARM).balance, 0);
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0);
    }

    function test_ClaimLidoWithdrawals_SingleRequest()
        public
        asOperator
        requestLidoWithdrawalsOnLidoARM(amounts1)
        mockFunctionClaimWithdrawOnLidoARM(DEFAULT_AMOUNT)
    {
        // Assertions before
        uint256 balanceBefore = weth.balanceOf(address(lidoARM));
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), DEFAULT_AMOUNT);

        stETHWithdrawal.getLastRequestId();
        uint256[] memory requests = new uint256[](1);
        requests[0] = stETHWithdrawal.getLastRequestId();

        uint256 lastIndex = stETHWithdrawal.getLastCheckpointIndex();
        uint256[] memory hintIds = stETHWithdrawal.findCheckpointHints(requests, 1, lastIndex);

        // Expected events
        vm.expectEmit({emitter: address(lidoARM)});
        emit LidoARM.ClaimLidoWithdrawals(requests);

        // Main call
        lidoARM.claimLidoWithdrawals(requests, hintIds);

        // Assertions after
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0);
        assertEq(weth.balanceOf(address(lidoARM)), balanceBefore + DEFAULT_AMOUNT);
    }

    function test_ClaimLidoWithdrawals_MultiRequest()
        public
        asOperator
        requestLidoWithdrawalsOnLidoARM(amounts2)
        mockCallLidoFindCheckpointHints
        mockFunctionClaimWithdrawOnLidoARM(amounts2[0] + amounts2[1])
    {
        // Assertions before
        uint256 balanceBefore = weth.balanceOf(address(lidoARM));
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), amounts2[0] + amounts2[1]);

        stETHWithdrawal.getLastRequestId();
        uint256[] memory requests = new uint256[](2);
        requests[0] = stETHWithdrawal.getLastRequestId() - 1;
        requests[1] = stETHWithdrawal.getLastRequestId();

        uint256 lastIndex = stETHWithdrawal.getLastCheckpointIndex();
        uint256[] memory hintIds = stETHWithdrawal.findCheckpointHints(requests, 1, lastIndex);

        // Expected events
        vm.expectEmit({emitter: address(lidoARM)});
        emit LidoARM.ClaimLidoWithdrawals(requests);

        // Main call
        lidoARM.claimLidoWithdrawals(requests, hintIds);

        // Assertions after
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0);
        assertEq(weth.balanceOf(address(lidoARM)), balanceBefore + amounts2[0] + amounts2[1]);
    }
}
