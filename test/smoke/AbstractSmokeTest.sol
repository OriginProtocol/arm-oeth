// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";

import {DeployManager} from "script/deploy/DeployManager.sol";
import {AddressResolver} from "contracts/utils/Addresses.sol";

abstract contract AbstractSmokeTest is Test {
    AddressResolver public resolver;
    DeployManager internal deployManager;

    constructor() {
        // Check if the PROVIDER_URL is set.
        require(vm.envExists("PROVIDER_URL"), "PROVIDER_URL not set");

        // Create a fork.
        vm.createSelectFork(vm.envString("PROVIDER_URL"));

        resolver = new AddressResolver();

        deployManager = new DeployManager();

        // Run deployments
        deployManager.setUp();
        deployManager.run();
    }
}
