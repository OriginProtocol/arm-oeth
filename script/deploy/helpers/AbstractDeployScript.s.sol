// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

// Foundry
import {Vm} from "forge-std/Vm.sol";

// Helpers
import {Logger} from "script/deploy/helpers/Logger.sol";
import {Resolver} from "script/deploy/helpers/Resolver.sol";
import {GovHelper} from "script/deploy/helpers/GovHelper.sol";
import {State, Contract, GovProposal} from "script/deploy/helpers/DeploymentTypes.sol";

// Script Base
import {Base} from "script/deploy/Base.s.sol";

/// @title AbstractDeployScript
/// @notice Base abstract contract for orchestrating smart contract deployments.
/// @dev This contract standardizes the deployment workflow, including environment management,
/// logging, address persistence, and governance proposal simulation.
abstract contract AbstractDeployScript is Base {
    using Logger for bool;

    /// @notice Name of the deployment script.
    string public name;
    /// @notice Address used to deploy the contracts.
    address public deployer;
    /// @notice List of contracts deployed during the current execution.
    Contract[] public contracts;
    /// @notice Structure containing the actions for a governance proposal.
    GovProposal public govProposal;

    /// @notice Initializes the script name and sets up logging preferences.
    /// @param _name The identifiable name of the deployment task.
    constructor(string memory _name) {
        name = _name;
        log = state != State.FORK_TEST || forcedLog;
    }

    /// @notice The main entry point for the deployment process.
    /// @dev Executes the deployment lifecycle: Setup -> Broadcast -> Execution -> Storage -> Governance.
    function run() external virtual {
        // 1. Determine the current execution state (FORK_TEST, FORK_DEPLOYING, REAL_DEPLOYING)
        state = resolver.getState();

        // 2. Retrieve the deployer address from environment variables
        require(vm.envExists("DEPLOYER_ADDRESS"), "DEPLOYER_ADDRESS not set in .env");
        deployer = vm.envAddress("DEPLOYER_ADDRESS");

        // Log the deployer info (show as simulation if in fork mode)
        log.logDeployer(deployer, state == State.FORK_TEST || state == State.FORK_DEPLOYING);

        // Initiate broadcast for real networks or prank for local simulations
        if (state == State.REAL_DEPLOYING) vm.startBroadcast(deployer);
        if (state == State.FORK_TEST || state == State.FORK_DEPLOYING) vm.startPrank(deployer);

        // 3. Execute the specific deployment logic implemented in the child contract
        log.section(string.concat("Executing: ", name));
        _execute();
        log.endSection();

        // 4. Stop broadcasting or pranking
        if (state == State.REAL_DEPLOYING) vm.stopBroadcast();
        if (state == State.FORK_TEST || state == State.FORK_DEPLOYING) vm.stopPrank();

        // 5. Persist the deployed contract addresses in the Resolver
        _storeDeployedContract();

        // 6. Construct the governance proposal if applicable
        _buildGovernanceProposal();

        // 7. Handle the governance proposal based on the current state
        if (govProposal.actions.length == 0) {
            log.info("No governance proposal to handle");
            return;
        }

        if (govProposal.actions.length != 0) {
            // For real deployments, output the proposal data for submission
            if (state == State.REAL_DEPLOYING) GovHelper.logProposalData(log, govProposal);
            // For forks/tests, simulate the execution of the proposal to ensure it works
            if (state == State.FORK_TEST || state == State.FORK_DEPLOYING) GovHelper.simulate(log, govProposal);
        }

        // 8. Run optional post-deployment fork simulations
        if (state == State.FORK_TEST || state == State.FORK_DEPLOYING) _fork();
    }

    /// @dev Records a newly deployed contract locally and logs the event.
    /// @param contractName The name of the contract.
    /// @param implementation The address where the contract was deployed.
    function _recordDeployment(string memory contractName, address implementation) internal virtual {
        contracts.push(Contract({implementation: implementation, name: contractName}));
        log.logContractDeployed(contractName, implementation);
    }

    /// @dev Iterates through recorded contracts and saves them into the global Resolver.
    function _storeDeployedContract() internal virtual {
        for (uint256 i = 0; i < contracts.length; i++) {
            resolver.addContract(contracts[i].name, contracts[i].implementation);
        }
        // Records that this specific script has been executed
        resolver.addExecution(name, block.timestamp);
    }

    /// @dev Hook to run custom logic on a fork after the deployment is finished.
    function _fork() internal virtual {}

    /// @dev Main deployment logic to be implemented by the inheriting contract.
    function _execute() internal virtual {}

    /// @dev Hook to define actions for a governance proposal (e.g., updating parameters).
    function _buildGovernanceProposal() internal virtual {}

    /// @notice Logic to determine if this script should be skipped.
    function skip() external view virtual returns (bool) {}

    /// @notice Logic to check if the associated governance proposal has already been executed on-chain.
    function proposalExecuted() external view virtual returns (bool) {}

    /// @notice Handles the final submission of the governance proposal.
    function handleGovernanceProposal() external virtual {}
}
