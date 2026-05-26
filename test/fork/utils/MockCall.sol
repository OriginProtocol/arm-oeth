// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {Vm} from "forge-std/Vm.sol";

import {IStETHWithdrawal} from "contracts/Interfaces.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

/// @notice This contract should be used to mock calls to other contracts.
library MockCall {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function mockCallDripperCollect(address dripper) external {
        vm.mockCall({callee: dripper, data: abi.encodeWithSignature("collect()"), returnData: abi.encode(true)});
    }

    function mockCallLidoFindCheckpointHints() external {
        vm.mockCall({
            callee: Mainnet.LIDO_WITHDRAWAL,
            data: abi.encodeWithSignature("findCheckpointHints(uint256[],uint256,uint256)"),
            returnData: abi.encode(new uint256[](1))
        });
    }

    function mockCallLidoClaimWithdrawals(address target) external {
        vm.mockFunction({
            callee: Mainnet.LIDO_WITHDRAWAL,
            target: target,
            data: abi.encodeWithSignature("claimWithdrawals(uint256[],uint256[])")
        });
        vm.mockFunction({
            callee: Mainnet.LIDO_WITHDRAWAL,
            target: target,
            data: abi.encodeWithSignature("getWithdrawalStatus(uint256[])")
        });
        vm.mockFunction({
            callee: Mainnet.LIDO_WITHDRAWAL, target: target, data: abi.encodeWithSignature("getLastCheckpointIndex()")
        });
        vm.mockFunction({
            callee: Mainnet.LIDO_WITHDRAWAL,
            target: target,
            data: abi.encodeWithSignature("findCheckpointHints(uint256[],uint256,uint256)")
        });
    }
}

contract MockLidoWithdraw {
    ETHSender public immutable ethSender;
    address public immutable adapter;

    constructor(address _adapter) {
        ethSender = new ETHSender();
        adapter = _adapter;
    }

    /// @notice Mock the call to the Lido contract's `claimWithdrawals` function.
    /// @dev as it is not possible to transfer ETH from the mocked contract (seems to be an issue with forge)
    /// we use the ETHSender contract intermediary to send the ETH to the target contract.
    function claimWithdrawals(uint256[] memory, uint256[] memory) external {
        ethSender.sendETH(msg.sender);
    }

    function getWithdrawalStatus(uint256[] calldata requestIds)
        external
        view
        returns (IStETHWithdrawal.WithdrawalRequestStatus[] memory statuses)
    {
        statuses = new IStETHWithdrawal.WithdrawalRequestStatus[](requestIds.length);
        for (uint256 i = 0; i < requestIds.length; ++i) {
            statuses[i] = IStETHWithdrawal.WithdrawalRequestStatus({
                amountOfStETH: 0, amountOfShares: 0, owner: adapter, timestamp: 0, isFinalized: true, isClaimed: false
            });
        }
    }

    /// @notice Mock the call to the Lido contract's `getLastCheckpointIndex` function.
    function getLastCheckpointIndex() public pure returns (uint256) {
        // hardcoded as this is not used by the Lido ARM
        return 300;
    }

    /// @notice Mock the call to the Lido contract's `findCheckpointHints` function.
    function findCheckpointHints(uint256[] calldata _requestIds, uint256, uint256)
        external
        pure
        returns (uint256[] memory hintIds)
    {
        hintIds = new uint256[](_requestIds.length);
        for (uint256 i = 0; i < _requestIds.length; ++i) {
            // hardcoded as this is not used by the Lido ARM
            hintIds[i] = 300;
        }
    }
}

contract ETHSender {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function sendETH(address target) external {
        vm.deal(target, target.balance + address(this).balance);
    }
}
