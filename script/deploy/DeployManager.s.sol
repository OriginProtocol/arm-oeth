// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

// Import Forge standard libraries
import {Vm} from "forge-std/Vm.sol";
import {VmSafe} from "forge-std/Vm.sol";

// Import helpers
import {Logger} from "script/deploy/helpers/Logger.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {State, Execution, Contract, Root} from "script/deploy/helpers/DeploymentTypes.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

// Import deployment scripts base
import {Base} from "script/deploy/Base.s.sol";

// Mainnet deployment scripts
import {UpgradeLidoARMMainnetScript} from "script/deploy/mainnet/003_UpgradeLidoARMScript.sol";
import {UpdateCrossPriceMainnetScript} from "script/deploy/mainnet/004_UpdateCrossPriceScript.sol";
import {RegisterLidoWithdrawalsScript} from "script/deploy/mainnet/005_RegisterLidoWithdrawalsScript.sol";
import {ChangeFeeCollectorScript} from "script/deploy/mainnet/006_ChangeFeeCollector.sol";
import {UpgradeLidoARMMorphoScript} from "script/deploy/mainnet/007_UpgradeLidoARMMorphoScript.sol";
import {DeployPendleAdaptor} from "script/deploy/mainnet/008_DeployPendleAdaptor.sol";
import {UpgradeLidoARMSetBufferScript} from "script/deploy/mainnet/009_UpgradeLidoARMSetBufferScript.sol";
import {UpgradeLidoARMAssetScript} from "script/deploy/mainnet/010_UpgradeLidoARMAssetScript.sol";
import {DeployEtherFiARMScript} from "script/deploy/mainnet/011_DeployEtherFiARMScript.sol";
import {UpgradeEtherFiARMScript} from "script/deploy/mainnet/012_UpgradeEtherFiARMScript.sol";
import {UpgradeOETHARMScript} from "script/deploy/mainnet/013_UpgradeOETHARMScript.sol";
import {DeployEthenaARMScript} from "script/deploy/mainnet/014_DeployEthenaARMScript.sol";
import {UpgradeEthenaARMScript} from "script/deploy/mainnet/015_UpgradeEthenaARMScript.sol";
import {UpgradeLidoARMCrossPriceScript} from "script/deploy/mainnet/016_UpdateLidoARMCrossPriceScript.sol";

// Sonic deployment scripts
import {DeployOriginARMProxyScript} from "script/deploy/sonic/001_DeployOriginARMProxy.sol";
import {DeployOriginARMScript} from "script/deploy/sonic/002_DeployOriginARM.sol";
import {UpgradeOriginARMScript} from "script/deploy/sonic/003_UpgradeOriginARM.sol";
import {DeployPendleAdaptorSonic} from "script/deploy/sonic/004_DeployPendleAdaptor.sol";
import {UpgradeOriginARMSetBufferScript} from "script/deploy/sonic/005_UpgradeOriginARMSetBufferScript.sol";

contract DeployManager is Base {
    using Logger for bool;

    string public forkFileId;
    string public deployment;

    function setUp() external virtual {
        // Determine deployment state
        setState();

        // Set logging based on state
        log = state != State.FORK_TEST || forcedLog;

        // Log deployment start info
        log.logSetup(chainNames[block.chainid], block.chainid);
        log.logKeyValue("State", _stateToString(state));

        // Get deployment file path
        string memory deployFilePath = getChainDeploymentFilePath();

        // Create deployment file if it doesn't exist
        if (!vm.isFile(deployFilePath)) {
            vm.writeFile(deployFilePath, '{"contracts": [], "executions": []}');
            log.info(string.concat("Created deployment file at: ", deployFilePath));
            deployment = vm.readFile(deployFilePath);
        }

        // If we are forking, duplicate the deployment file, to not interfere with the main deployment file
        // If the file already exists, it will be overwritten
        if (state == State.FORK_TEST || state == State.FORK_DEPLOYING) {
            forkFileId = string(abi.encodePacked(vm.toString(block.timestamp)));
            // Store deployment data in memory, because it will be read again in _preDeployment.
            vm.pauseTracing();
            deployment = vm.readFile(deployFilePath);
            vm.writeFile(getForkDeploymentFilePath(), deployment);
            vm.resumeTracing();
        }

        // Deploy Resolver contract in current environment
        deployResolver();
    }

    // --- Main deployment runner --- //
    function run() external virtual {
        _preDeployment();
        if (block.chainid == 1) {
            // Mainnet
            // Todo: fetch deployment list by reading all name file in script/mainnet/
            _runDeployFile(new UpgradeLidoARMMainnetScript());
            _runDeployFile(new UpdateCrossPriceMainnetScript());
            _runDeployFile(new RegisterLidoWithdrawalsScript());
            _runDeployFile(new ChangeFeeCollectorScript());
            _runDeployFile(new UpgradeLidoARMMorphoScript());
            _runDeployFile(new DeployPendleAdaptor());
            _runDeployFile(new UpgradeLidoARMSetBufferScript());
            _runDeployFile(new UpgradeLidoARMAssetScript());
            _runDeployFile(new DeployEtherFiARMScript());
            _runDeployFile(new UpgradeEtherFiARMScript());
            _runDeployFile(new UpgradeOETHARMScript());
            _runDeployFile(new DeployEthenaARMScript());
            _runDeployFile(new UpgradeEthenaARMScript());
            _runDeployFile(new UpgradeLidoARMCrossPriceScript());
            // Here
        } else if (block.chainid == 146) {
            // Sonic
            _runDeployFile(new DeployOriginARMProxyScript());
            _runDeployFile(new DeployOriginARMScript());
            _runDeployFile(new UpgradeOriginARMScript());
            _runDeployFile(new DeployPendleAdaptorSonic());
            _runDeployFile(new UpgradeOriginARMSetBufferScript());
        } else {
            revert("Unsupported chain");
        }
        _postDeployment();
    }

    function _runDeployFile(AbstractDeployScript deployFile) internal {
        // 1. Check if we need to skip
        if (deployFile.skip()) return;

        // 2. Check if proposal already executed
        if (deployFile.proposalExecuted()) return;

        // 3. Check if deployment is in deployment history (dumped in Resolver)
        string memory deployFileName = deployFile.name();
        bool alreadyDeployed = resolver.executionExists(deployFileName);

        // 4. Deploy the deployment contract
        // Need to label the deploy file for better logging
        vm.label(address(deployFile), deployFileName);

        // 5. At this point, the proposal has not been executed/finalized.
        // There are two possibilities:
        // - The deployment has been executed, but the proposal is still processing (5a).
        // - The deployment has not been executed yet: we can run it (5b).

        // 5.a If deployed, only manage governance proposal
        if (alreadyDeployed) {
            log.logSkip(deployFileName, "deployment already executed");
            log.info(string.concat("Handling governance proposal for ", deployFileName));
            deployFile.handleGovernanceProposal();
            return;
        }

        // 5.b If not deployed, run deployment
        deployFile.run();
    }

    function _preDeployment() internal pauseTracing {
        // Dump all data from build/deployments-<chainid>.json to the Resolver
        Root memory root = abi.decode(vm.parseJson(deployment), (Root));

        for (uint256 i = 0; i < root.contracts.length; i++) {
            resolver.addContract(root.contracts[i].name, root.contracts[i].implementation);
        }
        for (uint256 i = 0; i < root.executions.length; i++) {
            resolver.addExecution(root.executions[i].name, root.executions[i].timestamp);
        }
    }

    function _postDeployment() internal pauseTracing {
        // Dump all data from the Resolver to build/deployments-<chainid>.json
        Contract[] memory contracts = resolver.getContracts();
        Execution[] memory executions = resolver.getExecutions();

        string[] memory serializedContracts = new string[](contracts.length);
        string[] memory serializedExecutions = new string[](executions.length);

        for (uint256 i = 0; i < contracts.length; i++) {
            vm.serializeString("c_obj", "name", contracts[i].name);
            serializedContracts[i] = vm.serializeAddress("c_obj", "implementation", contracts[i].implementation);
        }

        for (uint256 i = 0; i < executions.length; i++) {
            vm.serializeString("e_obj", "name", executions[i].name);
            serializedExecutions[i] = vm.serializeUint("e_obj", "timestamp", executions[i].timestamp);
        }

        vm.serializeString("root", "contracts", serializedContracts);
        string memory finalJson = vm.serializeString("root", "executions", serializedExecutions);

        vm.writeFile(getDeploymentFilePath(), finalJson);
    }

    // --- Helper functions --- //
    function setState() public {
        // Is considered FORK_TEST:
        // - Test
        // - Coverage
        // - Snapshot
        //
        // Is considered FORK_DEPLOYING:
        // - Script Dry Run
        //
        // Is considered REAL_DEPLOYING:
        // - Script Resume
        // - Script Broadcast
        state = State.DEFAULT;
        if (vm.isContext(VmSafe.ForgeContext.TestGroup)) state = State.FORK_TEST;
        else if (vm.isContext(VmSafe.ForgeContext.ScriptDryRun)) state = State.FORK_DEPLOYING;
        else if (vm.isContext(VmSafe.ForgeContext.ScriptResume)) state = State.REAL_DEPLOYING;
        else if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) state = State.REAL_DEPLOYING;
        require(state != State.DEFAULT, "Unable to determine deployment state");
    }

    function deployResolver() public pauseTracing {
        bytes memory resolverCode = vm.getDeployedCode("Resolver.sol:Resolver");
        vm.etch(address(resolver), resolverCode);
        resolver.setState(state);
        vm.label(address(resolver), "Resolver");
    }

    // --- Deployment file view paths helpers --- //
    function getChainDeploymentFilePath() public view returns (string memory) {
        string memory chainIdStr = vm.toString(block.chainid);
        return string(abi.encodePacked(projectRoot, "/build/deployments-", chainIdStr, ".json"));
    }

    function getForkDeploymentFilePath() public view returns (string memory) {
        return string(abi.encodePacked(projectRoot, "/build/deployments-fork-", forkFileId, ".json"));
    }

    function getDeploymentFilePath() public view returns (string memory) {
        if (state == State.FORK_TEST || state == State.FORK_DEPLOYING) return getForkDeploymentFilePath();
        if (state == State.REAL_DEPLOYING) return getChainDeploymentFilePath();
        revert("Invalid state");
    }

    function _stateToString(State _state) internal pure returns (string memory) {
        if (_state == State.FORK_TEST) return "FORK_TEST";
        if (_state == State.FORK_DEPLOYING) return "FORK_DEPLOYING";
        if (_state == State.REAL_DEPLOYING) return "REAL_DEPLOYING";
        return "DEFAULT";
    }
}
