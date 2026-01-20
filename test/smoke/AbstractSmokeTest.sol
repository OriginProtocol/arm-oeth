// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Foundry imports
import {Test} from "forge-std/Test.sol";

import {DeployManager} from "script/deploy/DeployManager.s.sol";
import {Resolver} from "script/deploy/helpers/Resolver.sol";

abstract contract AbstractSmokeTest is Test {
    Resolver internal resolver = Resolver(address(uint160(uint256(keccak256("Resolver")))));

    DeployManager internal deployManager;

    constructor() {
        // Check if the PROVIDER_URL is set.
        require(vm.envExists("PROVIDER_URL"), "PROVIDER_URL not set");

        // Create a fork.
        vm.createSelectFork(vm.envString("PROVIDER_URL"));

        deployManager = new DeployManager();

        // Run deployments
        deployManager.setUp();
        deployManager.run();
    }
}
