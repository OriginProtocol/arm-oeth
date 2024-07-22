// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {Vm} from "forge-std/Vm.sol";

/// @notice This contract should be used to mock calls to other contracts.
library MockCall {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function mockCallDripperCollect(address dripper) external {
        vm.mockCall({callee: dripper, data: abi.encodeWithSignature("collect()"), returnData: abi.encode(true)});
    }
}
