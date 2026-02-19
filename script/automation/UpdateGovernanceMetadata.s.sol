// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

// Foundry
import {Script, console} from "forge-std/Script.sol";

// Types (read-only reuse)
import {
    Root,
    Execution,
    Contract,
    State,
    NO_GOVERNANCE,
    GOVERNANCE_PENDING
} from "script/deploy/helpers/DeploymentTypes.sol";
import {IGovernance} from "script/deploy/helpers/GovHelper.sol";
import {Resolver} from "script/deploy/helpers/Resolver.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

// Addresses
import {Mainnet} from "src/contracts/utils/Addresses.sol";

/// @title UpdateGovernanceMetadata
/// @notice Standalone script to update proposalId and tsGovernance in deployments-1.json.
/// @dev Runs as a CI job (every 6 hours) to fill in governance metadata after proposals
///      are submitted and executed on-chain.
///
///      Two cases handled:
///      - Case A: proposalId == 0 -> find proposalId via buildGovernanceProposal() + GovHelper.id()
///      - Case B: proposalId > 1 && tsGovernance == 0 -> find execution timestamp via FFI
contract UpdateGovernanceMetadata is Script {
    string constant DEPLOY_FILE = "build/deployments-1.json";

    IGovernance constant governance = IGovernance(Mainnet.GOVERNOR_SIX);

    // Resolver at the same deterministic address used by the deploy framework
    Resolver internal resolver = Resolver(address(uint160(uint256(keccak256("Resolver")))));

    // Raw JSON string stored in setUp() for parsing in run()
    string public deploymentJson;

    function setUp() public {
        deploymentJson = vm.readFile(string.concat(vm.projectRoot(), "/", DEPLOY_FILE));
    }

    function run() public {
        Root memory root = abi.decode(vm.parseJson(deploymentJson), (Root));
        _setupResolver(root);

        bool updated = false;

        for (uint256 i = 0; i < root.executions.length; i++) {
            Execution memory exec = root.executions[i];

            // Case A: proposalId == GOVERNANCE_PENDING -> governance pending, find proposalId
            if (exec.proposalId == GOVERNANCE_PENDING) {
                uint256 proposalId = _findProposalId(exec);
                if (proposalId > NO_GOVERNANCE) {
                    console.log("Found proposalId for %s: %s", exec.name, proposalId);
                    root.executions[i].proposalId = proposalId;
                    updated = true;

                    uint256 ts = _findExecutionTimestamp(proposalId, exec.tsDeployment);
                    if (ts > 0) {
                        console.log("  Also found execution timestamp: %s", ts);
                        root.executions[i].tsGovernance = ts;
                    }
                } else {
                    console.log("Proposal not yet submitted for %s, skipping", exec.name);
                }
            }
            // Case B: proposalId > NO_GOVERNANCE && tsGovernance == GOVERNANCE_PENDING -> find execution timestamp
            else if (exec.proposalId > NO_GOVERNANCE && exec.tsGovernance == GOVERNANCE_PENDING) {
                uint256 ts = _findExecutionTimestamp(exec.proposalId, exec.tsDeployment);
                if (ts > 0) {
                    console.log("Found execution timestamp for %s: %s", exec.name, ts);
                    root.executions[i].tsGovernance = ts;
                    updated = true;
                } else {
                    console.log("Proposal %s not yet executed, skipping", exec.name);
                }
            }
        }

        if (updated) {
            _writeDeploymentFile(root);
            console.log("Deployment file updated successfully");
        } else {
            console.log("No updates needed");
        }
    }

    // ==================== Case A: Find Proposal ID ==================== //

    /// @notice Find the proposalId for a deployment with proposalId == 0.
    /// @dev Deploys the script via vm.deployCode, calls buildGovernanceProposal() which
    ///      populates govProposal and returns GovHelper.id(govProposal).
    function _findProposalId(Execution memory exec) internal returns (uint256) {
        uint256 snapshotId = vm.snapshotState();

        string memory artifactPath = string.concat(vm.projectRoot(), "/out/", exec.name, ".s.sol/$", exec.name, ".json");

        address scriptAddr;
        try vm.deployCode(artifactPath) returns (address deployed) {
            scriptAddr = deployed;
        } catch {
            console.log("  Could not deploy script %s, skipping", exec.name);
            vm.revertToState(snapshotId);
            return 0;
        }

        uint256 proposalId;
        try AbstractDeployScript(scriptAddr).buildGovernanceProposal() returns (uint256 id) {
            proposalId = id;
        } catch {
            console.log("  buildGovernanceProposal() failed for %s, skipping", exec.name);
            vm.revertToState(snapshotId);
            return 0;
        }

        vm.revertToState(snapshotId);

        // Verify the proposal actually exists on-chain
        if (proposalId > NO_GOVERNANCE && governance.proposalSnapshot(proposalId) > 0) {
            return proposalId;
        }

        return 0;
    }

    // ==================== Case B: Find Execution Timestamp ==================== //

    /// @notice Find the execution timestamp for a governance proposal via FFI.
    function _findExecutionTimestamp(uint256 proposalId, uint256 tsDeployment) internal returns (uint256) {
        string[] memory cmd = new string[](6);
        cmd[0] = "bash";
        cmd[1] = string.concat(vm.projectRoot(), "/script/automation/find_gov_prop_execution_timestamp.sh");
        cmd[2] = vm.toString(proposalId);
        cmd[3] = vm.envString("MAINNET_URL");
        cmd[4] = vm.toString(Mainnet.GOVERNOR_SIX);
        cmd[5] = vm.toString(tsDeployment);

        bytes memory result = vm.ffi(cmd);
        return abi.decode(result, (uint256));
    }

    // ==================== Resolver Setup ==================== //

    /// @notice Set up the Resolver with data from the deployment file.
    function _setupResolver(Root memory root) internal {
        bytes memory resolverCode = vm.getDeployedCode("Resolver.sol:Resolver");
        vm.etch(address(resolver), resolverCode);
        resolver.setState(State.FORK_DEPLOYING);

        for (uint256 i = 0; i < root.contracts.length; i++) {
            resolver.addContract(root.contracts[i].name, root.contracts[i].implementation);
        }

        for (uint256 i = 0; i < root.executions.length; i++) {
            Execution memory exec = root.executions[i];
            resolver.addExecution(exec.name, exec.tsDeployment, exec.proposalId, exec.tsGovernance);
        }
    }

    // ==================== JSON Write-back ==================== //

    /// @notice Serialize and write the updated deployment data back to JSON.
    /// @dev Builds JSON manually instead of using vm.serializeUint because Foundry
    ///      quotes uint256 values exceeding 2^53 as strings, breaking the expected format.
    function _writeDeploymentFile(Root memory root) internal {
        string memory contractsJson = "";
        for (uint256 i = 0; i < root.contracts.length; i++) {
            if (i > 0) contractsJson = string.concat(contractsJson, ",\n");
            contractsJson = string.concat(
                contractsJson,
                '    {\n      "implementation": "',
                vm.toString(root.contracts[i].implementation),
                '",\n      "name": "',
                root.contracts[i].name,
                '"\n    }'
            );
        }

        string memory executionsJson = "";
        for (uint256 i = 0; i < root.executions.length; i++) {
            if (i > 0) executionsJson = string.concat(executionsJson, ",\n");
            string memory entry = string.concat('    {\n      "name": "', root.executions[i].name, '",\n');
            entry = string.concat(entry, '      "proposalId": ', vm.toString(root.executions[i].proposalId), ",\n");
            entry = string.concat(entry, '      "tsDeployment": ', vm.toString(root.executions[i].tsDeployment), ",\n");
            entry =
                string.concat(entry, '      "tsGovernance": ', vm.toString(root.executions[i].tsGovernance), "\n    }");
            executionsJson = string.concat(executionsJson, entry);
        }

        string memory json = string.concat('{\n  "contracts": [\n', contractsJson, '\n  ],\n  "executions": [\n');
        json = string.concat(json, executionsJson, "\n  ]\n}\n");

        vm.writeFile(string.concat(vm.projectRoot(), "/", DEPLOY_FILE), json);
    }
}
