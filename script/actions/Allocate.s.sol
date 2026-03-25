// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";

contract Allocate is Script {
    function run() external {
        string memory armAddress = vm.envString("ARM_ADDRESS");
        string memory threshold = vm.envOr("ARM_THRESHOLD", string(""));
        string memory maxGasPrice = vm.envOr("ARM_MAX_GAS_PRICE", string(""));
        string memory version = vm.envOr("ARM_CONTRACT_VERSION", string(""));

        // Build FFI command: node runner.js allocate <address> [--options]
        uint256 argCount = 4; // node, runner.js, allocate, address
        if (bytes(threshold).length > 0) argCount += 2;
        if (bytes(maxGasPrice).length > 0) argCount += 2;
        if (bytes(version).length > 0) argCount += 2;

        string[] memory cmd = new string[](argCount);
        uint256 i = 0;
        cmd[i++] = "node";
        cmd[i++] = string.concat(vm.projectRoot(), "/src/js/tasks/runner.js");
        cmd[i++] = "allocate";
        cmd[i++] = armAddress;

        if (bytes(threshold).length > 0) {
            cmd[i++] = "--threshold";
            cmd[i++] = threshold;
        }
        if (bytes(maxGasPrice).length > 0) {
            cmd[i++] = "--maxGasPrice";
            cmd[i++] = maxGasPrice;
        }
        if (bytes(version).length > 0) {
            cmd[i++] = "--armContractVersion";
            cmd[i++] = version;
        }

        bytes memory result = vm.ffi(cmd);

        (bool shouldExecute, address target, bytes memory callData) = abi.decode(result, (bool, address, bytes));

        if (!shouldExecute) {
            console.log("No allocation needed, skipping broadcast");
            return;
        }

        console.log("Allocating on ARM:", target);

        vm.startBroadcast();
        (bool success,) = target.call(callData);
        require(success, "allocate call failed");
        vm.stopBroadcast();
    }
}
