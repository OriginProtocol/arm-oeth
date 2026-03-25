// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";

contract CollectFees is Script {
    function run() external {
        string memory armAddress = vm.envString("ARM_ADDRESS");

        // Build FFI command: node runner.js collectFees <address>
        string[] memory cmd = new string[](4);
        cmd[0] = "node";
        cmd[1] = string.concat(vm.projectRoot(), "/src/js/tasks/runner.js");
        cmd[2] = "collectFees";
        cmd[3] = armAddress;

        bytes memory result = vm.ffi(cmd);

        (bool shouldExecute, address target, bytes memory callData) = abi.decode(result, (bool, address, bytes));

        if (!shouldExecute) {
            console.log("No fees to collect, skipping broadcast");
            return;
        }

        console.log("Collecting fees on ARM:", target);

        vm.startBroadcast();
        (bool success,) = target.call(callData);
        require(success, "collectFees call failed");
        vm.stopBroadcast();
    }
}
