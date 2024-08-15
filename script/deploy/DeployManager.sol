// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.23;

import "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {AbstractDeployScript} from "./AbstractDeployScript.sol";
import {DeployCoreMainnetScript} from "./mainnet/001_DeployCoreScript.sol";
import {UpgradeMainnetScript} from "./mainnet/002_UpgradeScript.sol";
import {DeployCoreHoleskyScript} from "./holesky/001_DeployCoreScript.sol";
import {UpgradeHoleskyScript} from "./holesky/002_UpgradeScript.sol";

contract DeployManager is Script {
    mapping(string => address) public deployedContracts;
    mapping(string => bool) public scriptsExecuted;

    string internal forkFileId = "";

    bool public isForked;

    constructor() {
        isForked = vm.isContext(VmSafe.ForgeContext.ScriptDryRun) || vm.isContext(VmSafe.ForgeContext.TestGroup);
        forkFileId = vm.toString(block.timestamp);
    }

    function getDeploymentFilePath() public view returns (string memory) {
        return isForked ? getForkDeploymentFilePath() : getChainDeploymentFilePath();
    }

    function getChainDeploymentFilePath() public view returns (string memory) {
        return string(abi.encodePacked(vm.projectRoot(), "/build/deployments.json"));
    }

    function getForkDeploymentFilePath() public view returns (string memory) {
        return string(abi.encodePacked(vm.projectRoot(), "/build/deployments-fork", forkFileId, ".json"));
    }

    function setForkFileId(string memory _forkFileId) external {
        forkFileId = _forkFileId;
    }

    function setUp() external {
        string memory chainIdStr = vm.toString(block.chainid);
        string memory chainIdKey = string(abi.encodePacked(".", chainIdStr));

        string memory deployFilePath = getChainDeploymentFilePath();
        if (!vm.isFile(deployFilePath)) {
            // Create deployment file if it doesn't exist
            vm.writeFile(
                deployFilePath,
                string(abi.encodePacked('{ "', chainIdStr, '": { "executions": {}, "contracts": {} } }'))
            );
        } else if (!vm.keyExistsJson(vm.readFile(deployFilePath), chainIdKey)) {
            // Create network entry if it doesn't exist
            vm.writeJson(
                vm.serializeJson(chainIdStr, '{ "executions": {}, "contracts": {} }'), deployFilePath, chainIdKey
            );
        }

        if (isForked) {
            // Duplicate deployment file
            vm.writeFile(getForkDeploymentFilePath(), vm.readFile(deployFilePath));
        }
    }

    function run() external {
        if (block.chainid == 1 || block.chainid == 31337) {
            // TODO: Use vm.readDir to recursively build this?
            _runDeployFile(new DeployCoreMainnetScript());
            _runDeployFile(new UpgradeMainnetScript(this));
        } else if (block.chainid == 17000) {
            _runDeployFile(new DeployCoreHoleskyScript());
            _runDeployFile(new UpgradeHoleskyScript(this));
        } else {
            console.log("Skipping deployment (not mainnet)");
        }
    }

    function _runDeployFile(AbstractDeployScript deployScript) internal {
        if (deployScript.proposalExecuted()) {
            // No action to do
            return;
        } else if (deployScript.skip()) {
            console.log("Skipping deployment (skip() == true)");
            return;
        }

        string memory chainIdStr = isForked ? "1" : vm.toString(block.chainid);
        string memory chainIdKey = string(abi.encodePacked(".", chainIdStr));

        string memory contractsKey = string(abi.encodePacked(chainIdKey, ".contracts"));
        string memory executionsKey = string(abi.encodePacked(chainIdKey, ".executions"));

        string memory deploymentsFilePath = getDeploymentFilePath();
        string memory fileContents = vm.readFile(deploymentsFilePath);

        /**
         * Execution History
         */
        string memory currentExecutions = "";
        string[] memory executionKeys = vm.parseJsonKeys(fileContents, executionsKey);

        for (uint256 i = 0; i < executionKeys.length; ++i) {
            uint256 deployedTimestamp =
                vm.parseJsonUint(fileContents, string(abi.encodePacked(executionsKey, ".", executionKeys[i])));

            currentExecutions = vm.serializeUint(executionsKey, executionKeys[i], deployedTimestamp);
            scriptsExecuted[executionKeys[i]] = true;
        }

        /**
         * Pre-deployment
         */
        string memory networkDeployments = "";
        string[] memory existingContracts = vm.parseJsonKeys(fileContents, contractsKey);
        for (uint256 i = 0; i < existingContracts.length; ++i) {
            address deployedAddr =
                vm.parseJsonAddress(fileContents, string(abi.encodePacked(contractsKey, ".", existingContracts[i])));

            networkDeployments = vm.serializeAddress(contractsKey, existingContracts[i], deployedAddr);

            deployedContracts[existingContracts[i]] = deployedAddr;

            deployScript.preloadDeployedContract(existingContracts[i], deployedAddr);
        }

        if (scriptsExecuted[deployScript.DEPLOY_NAME()]) {
            console.log("Skipping deployment (already deployed)");

            // Governance handling
            deployScript.handleGovernanceProposal();
        } else {
            // Deployment
            deployScript.setUp();
            deployScript.run();

            /**
             * Post-deployment
             */
            AbstractDeployScript.DeployRecord[] memory records = deployScript.getAllDeployRecords();

            for (uint256 i = 0; i < records.length; ++i) {
                string memory name = records[i].name;
                address addr = records[i].addr;

                console.log(string(abi.encodePacked("> Recorded Deploy of ", name, " at")), addr);
                networkDeployments = vm.serializeAddress(contractsKey, name, addr);
                deployedContracts[name] = addr;
            }

            /**
             * Write Execution History
             */
            currentExecutions = vm.serializeUint(executionsKey, deployScript.DEPLOY_NAME(), block.timestamp);

            // Write to file instead of using writeJson to avoid "EOF while parsing a value at line 1 column 0" error.
            vm.writeFile(
                getDeploymentFilePath(),
                string(
                    abi.encodePacked(
                        '{ "',
                        chainIdStr,
                        '": { "executions": ',
                        currentExecutions,
                        ', "contracts": ',
                        networkDeployments,
                        "}}"
                    )
                )
            );

            console.log("> Deployment addresses stored and Deploy script execution complete.");
        }
    }

    function getDeployment(string calldata contractName) external view returns (address) {
        return deployedContracts[contractName];
    }
}
