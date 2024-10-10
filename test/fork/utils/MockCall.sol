// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {Vm} from "forge-std/Vm.sol";

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
    }
}

contract MockLidoWithdraw {
    ETHSender public immutable ethSender;
    address public immutable lidoARM;

    constructor(address _lidoFixedPriceMulltiLpARM) {
        ethSender = new ETHSender();
        lidoARM = _lidoFixedPriceMulltiLpARM;
    }

    /// @notice Mock the call to the Lido contract's `claimWithdrawals` function.
    /// @dev as it is not possible to transfer ETH from the mocked contract (seems to be an issue with forge)
    /// we use the ETHSender contract intermediary to send the ETH to the target contract.
    function claimWithdrawals(uint256[] memory, uint256[] memory) external {
        ethSender.sendETH(lidoARM);
    }
}

contract ETHSender {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function sendETH(address target) external {
        vm.deal(target, address(this).balance);
    }
}
