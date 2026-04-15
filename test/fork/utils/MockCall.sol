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

    function mockCallLidoFindCheckpointHints(address target) external {
        vm.mockFunction({
            callee: Mainnet.LIDO_WITHDRAWAL,
            target: target,
            data: abi.encodeWithSignature("findCheckpointHints(uint256[],uint256,uint256)")
        });
    }

    function mockCallLidoClaimWithdrawals(address target) external {
        vm.mockFunction({
            callee: Mainnet.LIDO_WITHDRAWAL,
            target: target,
            data: abi.encodeWithSignature("claimWithdrawals(uint256[],uint256[])")
        });
    }

    function mockCallLidoGetWithdrawalStatus(address target) external {
        vm.mockFunction({
            callee: Mainnet.LIDO_WITHDRAWAL,
            target: target,
            data: abi.encodeWithSignature("getWithdrawalStatus(uint256[])")
        });
    }
}

contract MockLidoWithdraw {
    ETHSender public immutable ethSender;
    address public immutable receiver;

    constructor(address _receiver) {
        ethSender = new ETHSender();
        receiver = _receiver;
    }

    /// @notice Mock the call to the Lido contract's `claimWithdrawals` function.
    /// @dev as it is not possible to transfer ETH from the mocked contract (seems to be an issue with forge)
    /// we use the ETHSender contract intermediary to send the ETH to the target contract.
    function claimWithdrawals(uint256[] memory, uint256[] memory) external {
        ethSender.sendETH(receiver);
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

    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (IStETHWithdrawal.WithdrawalRequestStatus[] memory statuses)
    {
        statuses = IStETHWithdrawal(Mainnet.LIDO_WITHDRAWAL).getWithdrawalStatus(_requestIds);
        for (uint256 i = 0; i < statuses.length; ++i) {
            statuses[i].isFinalized = true;
            statuses[i].isClaimed = false;
        }
    }
}

contract ETHSender {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function sendETH(address target) external {
        vm.deal(target, address(this).balance);
    }
}
