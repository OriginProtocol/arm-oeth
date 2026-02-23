// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// ==================== Example Deployment Script ==================== //
//
// This file demonstrates all features of the deployment framework.
// Use it as a template when creating new deployment scripts.
//
// Naming Convention (IMPORTANT: all three MUST match or deployment silently breaks):
//   - File: NNN_DescriptiveName.sol (e.g., 015_UpgradeEthenaARM.sol)
//   - Contract: Same as file name, prefixed with $ (e.g., $015_UpgradeEthenaARM)
//   - Constructor arg: Same as contract name without $ (e.g., "015_UpgradeEthenaARM")
//
//   DeployManager constructs the artifact path as: out/{name}.s.sol/${name}.json
//   If the file name, contract name, or constructor arg drift, the script will
//   either fail to load or track execution under the wrong name.
//
// Execution Modes:
//   - FORK_TEST: Simulates deployment on fork, runs governance simulation
//   - FORK_DEPLOYING: Same as FORK_TEST, indicates ready for real deployment
//   - REAL_DEPLOYING: Actual on-chain deployment, outputs governance calldata
//
// ================================================================== //

// Contracts to deploy/upgrade
import {Proxy} from "contracts/Proxy.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {ZapperLidoARM} from "contracts/ZapperLidoARM.sol";

// Address constants
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment framework
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

/// @title $000_Example
/// @notice Example deployment script demonstrating all framework features.
/// @dev This script shows how to:
///      1. Deploy new contracts and register them
///      2. Look up previously deployed contracts via Resolver
///      3. Build governance proposals with multiple actions
///      4. Run post-deployment verification in fork mode
///
///      To create a new deployment script:
///      1. Copy this file and rename to NNN_YourScriptName.sol
///      2. Update contract name and constructor argument
///      3. Implement _execute() with your deployment logic
///      4. Implement _buildGovernanceProposal() if governance is needed
///      5. Implement _fork() for any post-deployment verification
contract $000_Example is AbstractDeployScript("000_Example") {
    using GovHelper for GovProposal;

    // ==================== Configuration ==================== //

    /// @notice Set to true to skip this script during deployment.
    /// @dev Useful for temporarily disabling scripts without removing them.
    ///      DeployManager checks this before running the script.
    bool public constant override skip = true; // Skip this example by default

    // ==================== State Variables ==================== //

    // Declare variables here for contracts deployed in _execute()
    // that need to be referenced in _buildGovernanceProposal() or _fork()
    LidoARM public newImplementation;

    // ==================== Main Deployment Logic ==================== //

    /// @notice Main deployment logic - deploy contracts and register them.
    /// @dev This function runs within vm.broadcast (real) or vm.prank (fork) context.
    ///      All transactions here will be executed by the deployer address.
    ///
    ///      Guidelines:
    ///      - Use resolver.resolve("NAME") to get previously deployed addresses
    ///      - Use _recordDeployment("NAME", address) to register new contracts
    ///      - Keep deployment logic simple; governance actions go in _buildGovernanceProposal()
    ///      - Contract names should be UPPER_SNAKE_CASE (e.g., "LIDO_ARM_IMPL")
    function _execute() internal override {
        // ===== Step 1: Retrieve Previously Deployed Contracts =====
        // Use the Resolver to look up contracts deployed by previous scripts.
        // This enables multi-script deployments where later scripts reference earlier ones.

        address lidoArmProxy = resolver.resolve("LIDO_ARM");
        address capManager = resolver.resolve("CAP_MANAGER");

        // You can also use Mainnet constants for external protocol addresses
        address weth = Mainnet.WETH;
        address steth = Mainnet.STETH;

        // ===== Step 2: Deploy New Contracts =====
        // Deploy your contracts here. The deployer address is already set via
        // vm.broadcast (real) or vm.prank (fork).

        // Example: Deploy a new implementation contract
        newImplementation = new LidoARM(steth, weth, Mainnet.LIDO_WITHDRAWAL, 10 minutes, 0, 0);

        // Example: Deploy a proxy with implementation
        // Proxy proxy = new Proxy();
        // proxy.initialize(address(newImplementation), owner, initData);

        // ===== Step 3: Register Deployed Contracts =====
        // Call _recordDeployment() for each contract that should be:
        // - Saved to the deployments JSON file
        // - Available to subsequent scripts via resolver.resolve()
        // - Logged for visibility

        _recordDeployment("LIDO_ARM_IMPL", address(newImplementation));

        // Note: You can register multiple contracts
        // _recordDeployment("MY_PROXY", address(proxy));
        // _recordDeployment("MY_HELPER", address(helper));
    }

    // ==================== Governance Proposal ==================== //

    /// @notice Builds the governance proposal for post-deployment configuration.
    /// @dev This function defines actions that require governance execution.
    ///      Actions are executed in order when the proposal passes.
    ///
    ///      In REAL_DEPLOYING mode: Calldata is output for manual submission
    ///      In FORK_TEST/FORK_DEPLOYING mode: Proposal is simulated end-to-end
    ///
    ///      Common governance actions:
    ///      - Proxy upgrades: proxy.upgradeTo(newImpl)
    ///      - Ownership transfers: contract.transferOwnership(newOwner)
    ///      - Configuration updates: contract.setConfig(value)
    ///      - Access control: contract.grantRole(role, account)
    function _buildGovernanceProposal() internal override {
        // ===== Set Proposal Description =====
        // This description is included on-chain and affects the proposal ID.
        // Be descriptive about what the proposal does.
        govProposal.setDescription("Example: Upgrade LidoARM Implementation");

        // ===== Add Governance Actions =====
        // Each action specifies:
        // - target: Contract address to call
        // - signature: Function signature (e.g., "upgradeTo(address)")
        // - data: ABI-encoded parameters (use abi.encode())

        // Example 1: Upgrade a proxy to new implementation
        address lidoArmProxy = resolver.resolve("LIDO_ARM");
        govProposal.action(lidoArmProxy, "upgradeTo(address)", abi.encode(address(newImplementation)));

        // Example 2: Set a configuration value
        // address capManager = resolver.resolve("CAP_MANAGER");
        // govProposal.action(
        //     capManager,
        //     "setTotalAssetsCap(uint248)",
        //     abi.encode(100 ether)
        // );

        // Example 3: Transfer ownership
        // govProposal.action(
        //     address(newContract),
        //     "transferOwnership(address)",
        //     abi.encode(Mainnet.GOVERNOR_SIX)
        // );

        // Example 4: Multiple parameter function
        // govProposal.action(
        //     targetAddress,
        //     "setPrices(uint256,uint256)",
        //     abi.encode(minPrice, maxPrice)
        // );
    }

    // ==================== Fork Testing ==================== //

    /// @notice Post-deployment verification logic for fork testing.
    /// @dev This function runs AFTER governance proposal simulation completes.
    ///      Only called in FORK_TEST and FORK_DEPLOYING modes.
    ///
    ///      Use this to verify:
    ///      - Deployment was successful
    ///      - Configuration is correct
    ///      - Integrations work as expected
    ///      - State transitions are valid
    ///
    ///      You can use vm.prank() here for additional test interactions.
    function _fork() internal override {
        // ===== Retrieve Deployed Contracts =====
        // address lidoArmProxy = resolver.resolve("LIDO_ARM");
        // LidoARM arm = LidoARM(payable(lidoArmProxy));

        // ===== Verify Upgrade Was Successful =====
        // Check that the proxy now points to the new implementation
        // address currentImpl = Proxy(payable(lidoArmProxy)).implementation();
        // require(currentImpl == address(newImplementation), "Implementation not upgraded");

        // ===== Verify Contract State =====
        // Check important state variables and configurations
        // require(arm.owner() == expectedOwner, "Owner mismatch");
        // require(arm.someConfig() == expectedValue, "Config mismatch");

        // ===== Test Interactions =====
        // Simulate user interactions to verify functionality
        // vm.prank(someUser);
        // arm.someFunction();

        // ===== Integration Tests =====
        // Verify integrations with other contracts work correctly
        // uint256 balance = arm.totalAssets();
        // require(balance > 0, "No assets");
    }
}
