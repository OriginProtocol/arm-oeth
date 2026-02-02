// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

// Foundry
import {Vm} from "forge-std/Vm.sol";
import {VmSafe} from "forge-std/Vm.sol";

// Helpers
import {Logger} from "script/deploy/helpers/Logger.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, IGovernance} from "script/deploy/helpers/GovHelper.sol";
import {State, Execution, Contract, Root, GovProposal} from "script/deploy/helpers/DeploymentTypes.sol";

// Script Base
import {Base} from "script/deploy/Base.s.sol";

// Utils
import {Mainnet} from "src/contracts/utils/Addresses.sol";

/// @title UpdateGovernance
/// @notice CLI tool to check on-chain governance state and update deployment JSON.
/// @dev Forks mainnet at latest block, iterates over executions with timestampGov == 0,
///      checks if their governance proposals have been executed on-chain, and updates the JSON.
///
///      Usage: make update-governance
contract UpdateGovernance is Base {
    using Logger for bool;

    // Raw JSON content of the deployment file
    string public deployment;

    /// @notice Initializes the governance update environment.
    function setUp() external {
        log = true;
        state = State.FORK_TEST;

        log.header("Update Governance Timestamps");

        // Build path to chain-specific deployment file
        string memory deployFilePath = getChainDeploymentFilePath();
        require(vm.isFile(deployFilePath), "Deployment file not found");
        deployment = vm.readFile(deployFilePath);

        // Deploy the Resolver contract
        deployResolver();
    }

    /// @notice Main entry point — checks governance state and updates JSON.
    function run() external {
        // Parse the JSON deployment file into structured data
        Root memory root;
        {
            vm.pauseTracing();
            root = abi.decode(vm.parseJson(deployment), (Root));
            vm.resumeTracing();
        }

        // Load all data into Resolver
        vm.pauseTracing();
        for (uint256 i = 0; i < root.contracts.length; i++) {
            resolver.addContract(root.contracts[i].name, root.contracts[i].implementation);
        }
        for (uint256 i = 0; i < root.executions.length; i++) {
            resolver.addExecution(
                root.executions[i].name, root.executions[i].timestampDep, root.executions[i].timestampGov
            );
        }
        vm.resumeTracing();

        // Read deployment script files
        string memory path;
        if (block.chainid == 1) {
            path = string(abi.encodePacked(projectRoot, "/script/deploy/mainnet/"));
        } else if (block.chainid == 146) {
            path = string(abi.encodePacked(projectRoot, "/script/deploy/sonic/"));
        } else {
            revert("Unsupported chain");
        }

        vm.pauseTracing();
        VmSafe.DirEntry[] memory files = vm.readDir(path);
        vm.resumeTracing();

        IGovernance governance = IGovernance(Mainnet.GOVERNOR_SIX);
        bool anyUpdated = false;

        // Check each execution with pending governance
        for (uint256 i = 0; i < root.executions.length; i++) {
            if (root.executions[i].timestampGov != 0) continue;

            string memory execName = root.executions[i].name;
            log.info(string.concat("Checking governance for: ", execName));

            // Find and deploy the corresponding script file
            address scriptAddr = _findAndDeployScript(files, execName);
            if (scriptAddr == address(0)) {
                log.warn(string.concat("Script file not found for: ", execName));
                continue;
            }

            // Build the governance proposal (without simulating)
            AbstractDeployScript deployFile = AbstractDeployScript(scriptAddr);
            GovProposal memory prop;
            try deployFile.buildGovernanceProposal() returns (GovProposal memory p) {
                prop = p;
            } catch {
                log.warn(string.concat("Failed to build proposal for: ", execName));
                continue;
            }

            // If no governance actions, mark as complete
            if (prop.actions.length == 0) {
                root.executions[i].timestampGov = root.executions[i].timestampDep;
                resolver.addGovernanceTimestamp(execName, root.executions[i].timestampDep);
                log.success(string.concat("No governance needed for: ", execName));
                anyUpdated = true;
                continue;
            }

            // Compute proposal ID and check on-chain state
            uint256 proposalId = GovHelper.id(prop);
            IGovernance.ProposalState propState = governance.state(proposalId);
            log.logKeyValue("  Proposal ID", proposalId);
            log.logKeyValue("  Proposal state", _stateToString(propState));

            if (propState == IGovernance.ProposalState.Executed) {
                root.executions[i].timestampGov = block.timestamp;
                resolver.addGovernanceTimestamp(execName, block.timestamp);
                log.success(string.concat("Governance executed for: ", execName));
                anyUpdated = true;
            } else {
                log.info(string.concat("Governance still pending for: ", execName));
            }
        }

        if (!anyUpdated) {
            log.info("No governance timestamps to update");
            return;
        }

        // Write updated JSON
        _writeDeploymentJson(root);
        log.success("Deployment JSON updated");
    }

    // ==================== Helper Functions ==================== //

    /// @notice Finds and deploys a script by its execution name.
    function _findAndDeployScript(VmSafe.DirEntry[] memory files, string memory execName) internal returns (address) {
        vm.pauseTracing();
        for (uint256 i = 0; i < files.length; i++) {
            if (files[i].isDir) continue;

            string memory scriptName = _extractScriptName(files[i].path);

            // Deploy the script and check if its execution name matches
            string memory contractName =
                string(abi.encodePacked(projectRoot, "/out/", scriptName, ".s.sol/$", scriptName, ".json"));
            try vm.deployCode(contractName) returns (address addr) {
                AbstractDeployScript script = AbstractDeployScript(addr);
                if (keccak256(bytes(script.name())) == keccak256(bytes(execName))) {
                    vm.resumeTracing();
                    return addr;
                }
            } catch {}
        }
        vm.resumeTracing();
        return address(0);
    }

    /// @notice Writes deployment data back to JSON.
    function _writeDeploymentJson(Root memory root) internal {
        vm.pauseTracing();

        Contract[] memory contracts_ = root.contracts;
        Execution[] memory executions = root.executions;

        string[] memory serializedContracts = new string[](contracts_.length);
        string[] memory serializedExecutions = new string[](executions.length);

        for (uint256 i = 0; i < contracts_.length; i++) {
            vm.serializeString("c_obj", "name", contracts_[i].name);
            serializedContracts[i] = vm.serializeAddress("c_obj", "implementation", contracts_[i].implementation);
        }

        for (uint256 i = 0; i < executions.length; i++) {
            vm.serializeString("e_obj", "name", executions[i].name);
            vm.serializeUint("e_obj", "timestampDep", executions[i].timestampDep);
            serializedExecutions[i] = vm.serializeUint("e_obj", "timestampGov", executions[i].timestampGov);
        }

        vm.serializeString("root", "contracts", serializedContracts);
        string memory finalJson = vm.serializeString("root", "executions", serializedExecutions);

        vm.writeFile(getChainDeploymentFilePath(), finalJson);
        vm.resumeTracing();
    }

    /// @notice Deploys the Resolver contract to a deterministic address.
    function deployResolver() public {
        vm.pauseTracing();
        bytes memory resolverCode = vm.getDeployedCode("Resolver.sol:Resolver");
        vm.etch(address(resolver), resolverCode);
        resolver.setState(state);
        vm.label(address(resolver), "Resolver");
        vm.resumeTracing();
    }

    /// @notice Returns the path to the main deployment file for the current chain.
    function getChainDeploymentFilePath() public view returns (string memory) {
        string memory chainIdStr = vm.toString(block.chainid);
        return string(abi.encodePacked(projectRoot, "/build/deployments-", chainIdStr, ".json"));
    }

    /// @notice Converts governance proposal state to string.
    function _stateToString(IGovernance.ProposalState _state) internal pure returns (string memory) {
        if (_state == IGovernance.ProposalState.Pending) return "Pending";
        if (_state == IGovernance.ProposalState.Active) return "Active";
        if (_state == IGovernance.ProposalState.Canceled) return "Canceled";
        if (_state == IGovernance.ProposalState.Defeated) return "Defeated";
        if (_state == IGovernance.ProposalState.Succeeded) return "Succeeded";
        if (_state == IGovernance.ProposalState.Queued) return "Queued";
        if (_state == IGovernance.ProposalState.Expired) return "Expired";
        if (_state == IGovernance.ProposalState.Executed) return "Executed";
        return "Unknown";
    }
}
