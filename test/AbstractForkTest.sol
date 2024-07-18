// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";

import {DeployManager} from "script/deploy/DeployManager.sol";

abstract contract AbstractForkTest is Test {
    DeployManager internal deployManager;

    constructor() {
        deployManager = new DeployManager();

        // Run deployments
        deployManager.setUp();
        deployManager.run();

        revert("1234");
    }
}
