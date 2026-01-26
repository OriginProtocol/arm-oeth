// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {State, Execution, Contract, Position} from "script/deploy/helpers/DeploymentTypes.sol";

/// @title Resolver
/// @notice Central registry for deployed contracts and execution history during deployments.
/// @dev This contract serves as an in-memory database during the deployment process:
///      - Stores addresses of deployed contracts for cross-script lookups
///      - Tracks which deployment scripts have been executed to prevent re-runs
///      - Deployed via vm.etch at a deterministic address for consistent access
///
///      Workflow:
///      1. DeployManager loads existing data from JSON into Resolver (_preDeployment)
///      2. Deployment scripts query Resolver for previously deployed addresses
///      3. Deployment scripts register new contracts and mark themselves as executed
///      4. DeployManager saves Resolver data back to JSON (_postDeployment)
contract Resolver {
    // ==================== State Variables ==================== //

    // Current deployment state (FORK_TEST, FORK_DEPLOYING, or REAL_DEPLOYING)
    // Used by scripts to adjust behavior based on execution context
    State public currentState;

    // Array of all registered contracts (for JSON serialization)
    // Maintains insertion order for consistent output
    Contract[] public contracts;

    // Array of all execution records (for JSON serialization)
    // Each entry represents a deployment script that has been run
    Execution[] public executions;

    // Tracks position of contracts in the array by name
    // Enables O(1) lookups and updates for existing contracts
    mapping(string => Position) public inContracts;

    // Quick lookup to check if a deployment script was already executed
    // Key: script name (e.g., "015_UpgradeEthenaARMScript")
    mapping(string => bool) public executionExists;

    // Quick lookup for deployed contract addresses by name
    // Key: contract name (e.g., "LIDO_ARM", "ETHENA_ARM_IMPL")
    // Value: deployed address
    mapping(string => address) public implementations;

    // ==================== Events ==================== //

    /// @notice Emitted when a new execution record is added
    /// @param name The name of the deployment script
    /// @param timestamp The block timestamp when the script was executed
    event ExecutionAdded(string name, uint256 timestamp);

    /// @notice Emitted when a contract address is registered or updated
    /// @param name The identifier for the contract
    /// @param implementation The deployed address
    event ContractAdded(string name, address implementation);

    // ==================== Contract Management ==================== //

    /// @notice Registers or updates a deployed contract address.
    /// @dev If the contract name already exists, updates the address (useful for upgrades).
    ///      If it's new, adds to both the array and mapping.
    ///      Always updates the implementations mapping for quick lookups.
    /// @param name The identifier for the contract (e.g., "LIDO_ARM", "ETHENA_ARM_IMPL")
    /// @param implementation The deployed contract address
    function addContract(string memory name, address implementation) external {
        // Check if this contract name was already registered
        Position memory pos = inContracts[name];

        if (!pos.exists) {
            // New contract: add to array and record its position
            contracts.push(Contract({name: name, implementation: implementation}));
            inContracts[name] = Position({index: contracts.length - 1, exists: true});
        } else {
            // Existing contract: update the address in place (e.g., after upgrade)
            contracts[pos.index].implementation = implementation;
        }

        // Always update the quick lookup mapping
        implementations[name] = implementation;

        emit ContractAdded(name, implementation);
    }

    // ==================== Execution Management ==================== //

    /// @notice Records that a deployment script has been executed.
    /// @dev Prevents duplicate executions by reverting if already recorded.
    ///      Called by deployment scripts after successful execution.
    /// @param name The unique name of the deployment script (e.g., "015_UpgradeEthenaARMScript")
    /// @param timestamp The block timestamp of execution
    function addExecution(string memory name, uint256 timestamp) external {
        // Prevent duplicate execution records
        require(!executionExists[name], "Execution already exists");

        // Add to array for JSON serialization
        executions.push(Execution({name: name, timestamp: timestamp}));

        // Mark as executed for quick lookups
        executionExists[name] = true;

        emit ExecutionAdded(name, timestamp);
    }

    // ==================== View Functions ==================== //

    /// @notice Returns all registered contracts.
    /// @dev Used by DeployManager._postDeployment() to serialize to JSON.
    /// @return Array of all Contract structs (name + implementation address)
    function getContracts() external view returns (Contract[] memory) {
        return contracts;
    }

    /// @notice Returns all execution records.
    /// @dev Used by DeployManager._postDeployment() to serialize to JSON.
    /// @return Array of all Execution structs (name + timestamp)
    function getExecutions() external view returns (Execution[] memory) {
        return executions;
    }

    // ==================== State Management ==================== //

    /// @notice Sets the current deployment state.
    /// @dev Called by DeployManager.deployResolver() after etching the contract.
    ///      Scripts can query this to adjust behavior (e.g., skip certain actions in tests).
    /// @param newState The deployment state (FORK_TEST, FORK_DEPLOYING, or REAL_DEPLOYING)
    function setState(State newState) external {
        currentState = newState;
    }

    /// @notice Returns the current deployment state.
    /// @return The current State enum value
    function getState() external view returns (State) {
        return currentState;
    }
}
