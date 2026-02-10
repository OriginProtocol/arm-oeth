// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.23;

import "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {AbstractDeployScript} from "./AbstractDeployScript.sol";
import {UpgradeLidoARMMainnetScript} from "./mainnet/003_UpgradeLidoARMScript.sol";
import {UpdateCrossPriceMainnetScript} from "./mainnet/004_UpdateCrossPriceScript.sol";
import {RegisterLidoWithdrawalsScript} from "./mainnet/005_RegisterLidoWithdrawalsScript.sol";
import {ChangeFeeCollectorScript} from "./mainnet/006_ChangeFeeCollector.sol";
import {DeployOriginARMProxyScript} from "./sonic/001_DeployOriginARMProxy.sol";
import {DeployOriginARMScript} from "./sonic/002_DeployOriginARM.sol";
import {UpgradeOriginARMScript} from "./sonic/003_UpgradeOriginARM.sol";
import {UpgradeLidoARMMorphoScript} from "./mainnet/007_UpgradeLidoARMMorphoScript.sol";
import {DeployPendleAdaptor} from "./mainnet/008_DeployPendleAdaptor.sol";
import {DeployPendleAdaptorSonic} from "./sonic/004_DeployPendleAdaptor.sol";
import {UpgradeLidoARMSetBufferScript} from "./mainnet/009_UpgradeLidoARMSetBufferScript.sol";
import {UpgradeOriginARMSetBufferScript} from "./sonic/005_UpgradeOriginARMSetBufferScript.sol";
import {UpgradeLidoARMAssetScript} from "./mainnet/010_UpgradeLidoARMAssetScript.sol";
import {DeployEtherFiARMScript} from "./mainnet/011_DeployEtherFiARMScript.sol";
import {UpgradeEtherFiARMScript} from "./mainnet/012_UpgradeEtherFiARMScript.sol";
import {UpgradeOETHARMScript} from "./mainnet/013_UpgradeOETHARMScript.sol";
import {DeployEthenaARMScript} from "./mainnet/014_DeployEthenaARMScript.sol";
import {UpgradeEthenaARMScript} from "./mainnet/015_UpgradeEthenaARMScript.sol";
import {UpgradeLidoARMCrossPriceScript} from "./mainnet/016_UpdateLidoARMCrossPriceScript.sol";
import {DeployNewMorphoMarketForEtherFiARM} from "./mainnet/017_DeployNewMorphoMarketForEtherFiARM.sol";
import {DeployNewMorphoMarketForLidoARM} from "./mainnet/018_DeployNewMorphoMarketForLidoARM.sol";
import {EmptyScript} from "./mainnet/999_empty.sol";

contract DeployManager is Script {
    using stdJson for string;

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
        string memory chainIdStr = vm.toString(block.chainid);
        return string(abi.encodePacked(vm.projectRoot(), "/build/deployments-", chainIdStr, ".json"));
    }

    function getForkDeploymentFilePath() public view returns (string memory) {
        return string(abi.encodePacked(vm.projectRoot(), "/build/deployments-fork", forkFileId, ".json"));
    }

    function setForkFileId(string memory _forkFileId) external {
        forkFileId = _forkFileId;
    }

    function setUp() external {
        string memory deployFilePath = getChainDeploymentFilePath();
        if (!vm.isFile(deployFilePath)) {
            // Create deployment file if it doesn't exist
            vm.writeFile(deployFilePath, string(abi.encodePacked('{"executions": {}, "contracts": {} }')));
        }

        if (isForked) {
            // Duplicate deployment file
            vm.writeFile(getForkDeploymentFilePath(), vm.readFile(deployFilePath));
        }
    }

    function run() external {
        if (block.chainid == 1 || block.chainid == 31337) {
            // TODO: Use vm.readDir to recursively build this?
            _runDeployFile(new UpgradeLidoARMMainnetScript());
            _runDeployFile(new UpdateCrossPriceMainnetScript());
            _runDeployFile(new RegisterLidoWithdrawalsScript());
            _runDeployFile(new ChangeFeeCollectorScript());
            _runDeployFile(new UpgradeLidoARMMorphoScript());
            _runDeployFile(new UpgradeLidoARMSetBufferScript());
            _runDeployFile(new DeployPendleAdaptor());
            _runDeployFile(new UpgradeLidoARMAssetScript());
            _runDeployFile(new DeployEtherFiARMScript());
            _runDeployFile(new UpgradeEtherFiARMScript());
            _runDeployFile(new UpgradeOETHARMScript());
            _runDeployFile(new DeployEthenaARMScript());
            _runDeployFile(new UpgradeEthenaARMScript());
            _runDeployFile(new UpgradeLidoARMCrossPriceScript());
            _runDeployFile(new DeployNewMorphoMarketForEtherFiARM());
            _runDeployFile(new DeployNewMorphoMarketForLidoARM());
            _runDeployFile(new EmptyScript());
        } else if (block.chainid == 17000) {
            // Holesky
        } else if (block.chainid == 146) {
            // Sonic
            console.log("Deploying Origin ARM");
            _runDeployFile(new DeployOriginARMProxyScript());
            _runDeployFile(new DeployOriginARMScript(getDeployedAddressInBuild("ORIGIN_ARM")));
            _runDeployFile(
                new UpgradeOriginARMScript(
                    getDeployedAddressInBuild("HARVESTER"),
                    getDeployedAddressInBuild("ORIGIN_ARM"),
                    getDeployedAddressInBuild("SILO_VARLAMORE_S_MARKET")
                )
            );
            _runDeployFile(new UpgradeOriginARMSetBufferScript(getDeployedAddressInBuild("ORIGIN_ARM")));
            _runDeployFile(new DeployPendleAdaptorSonic());
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

        string memory contractsKey = ".contracts";
        string memory executionsKey = ".executions";

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
                    abi.encodePacked('{"executions": ', currentExecutions, ', "contracts": ', networkDeployments, "}")
                )
            );

            console.log("> Deployment addresses stored and Deploy script execution complete.");
        }
    }

    function getDeployment(string memory contractName) public view returns (address) {
        return deployedContracts[contractName];
    }

    function getDeployedAddressInBuild(string memory contractName) public view returns (address) {
        string memory json = vm.readFile(getDeploymentFilePath());
        string memory key = string(abi.encodePacked("$.contracts.", contractName));
        require(json.keyExists(key), string(abi.encodePacked("Key ", contractName, " does not exist in JSON file")));
        return json.readAddress(key);
    }
}
