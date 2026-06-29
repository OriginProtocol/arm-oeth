// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Foundry imports
import {Test} from "forge-std/Test.sol";

import {Resolver} from "script/deploy/helpers/Resolver.sol";
import {DeployManager} from "script/deploy/DeployManager.s.sol";

abstract contract AbstractSmokeTest is Test {
    uint256 internal constant FEE_SCALE = 10000;
    uint256 internal constant DELAY_REQUEST = 30 minutes;

    Resolver internal resolver = Resolver(address(uint160(uint256(keccak256("Resolver")))));

    DeployManager internal deployManager;

    /// @notice Using setUp here instead of a constructor because in case of failing test,
    ///         constructors logs are not printed, while setUp logs are printed.
    function setUp() public virtual {
        // Check if the MAINNET_URL is set.
        require(vm.envExists("MAINNET_URL"), "MAINNET_URL not set");

        // Create a fork.
        // If block number is provided in the environment variables, use it.
        // Otherwise, use latest block.
        if (vm.envExists("FORK_BLOCK_NUMBER_MAINNET")) {
            uint256 blockNumber = vm.envUint("FORK_BLOCK_NUMBER_MAINNET");
            vm.createSelectFork(vm.envString("MAINNET_URL"), blockNumber);
        } else {
            vm.createSelectFork(vm.envString("MAINNET_URL"));
        }

        deployManager = new DeployManager();

        // Run deployments
        deployManager.setUp();
        deployManager.run();
    }
}
