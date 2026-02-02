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

    // Quick lookup for deployed contract addresses by name
    // Key: contract name (e.g., "LIDO_ARM", "ETHENA_ARM_IMPL")
    // Value: deployed address
    mapping(string => address) public implementations;

    // Quick lookup for execution index by name (for governance timestamp updates)
    // Key: script name, Value: index in executions array
    mapping(string => uint256) public executionIndex;

    // Quick lookup for deployment timestamp by script name
    // 0 means never deployed
    mapping(string => uint256) public depTimestamp;

    // Quick lookup for governance timestamp by script name
    // 0 means governance not yet executed
    mapping(string => uint256) public govTimestamp;

    // ==================== Events ==================== //

    /// @notice Emitted when a new execution record is added
    /// @param name The name of the deployment script
    /// @param timestampDep The block timestamp when the script was executed
    /// @param timestampGov The timestamp when governance was executed (0 if pending)
    event ExecutionAdded(string name, uint256 timestampDep, uint256 timestampGov);

    /// @notice Emitted when a governance timestamp is updated for an existing execution
    /// @param name The name of the deployment script
    /// @param timestampGov The timestamp when governance was executed
    event GovernanceTimestampUpdated(string name, uint256 timestampGov);

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
    /// @dev Called by deployment scripts after successful execution, or by DeployManager
    ///      when loading execution history from JSON.
    /// @param name The unique name of the deployment script (e.g., "015_UpgradeEthenaARMScript")
    /// @param _timestampDep The block timestamp of execution
    /// @param _timestampGov The timestamp when governance was executed (0 if pending)
    function addExecution(string memory name, uint256 _timestampDep, uint256 _timestampGov) external {
        executionIndex[name] = executions.length;
        executions.push(Execution({name: name, timestampDep: _timestampDep, timestampGov: _timestampGov}));
        depTimestamp[name] = _timestampDep;
        govTimestamp[name] = _timestampGov;

        emit ExecutionAdded(name, _timestampDep, _timestampGov);
    }

    /// @notice Updates the governance timestamp for an existing execution.
    /// @dev Called when a governance proposal is confirmed as executed on-chain.
    /// @param name The unique name of the deployment script
    /// @param _timestampGov The timestamp when governance was executed
    function addGovernanceTimestamp(string memory name, uint256 _timestampGov) external {
        executions[executionIndex[name]].timestampGov = _timestampGov;
        govTimestamp[name] = _timestampGov;

        emit GovernanceTimestampUpdated(name, _timestampGov);
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
    /// @return Array of all Execution structs (name + timestampDep + timestampGov)
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
