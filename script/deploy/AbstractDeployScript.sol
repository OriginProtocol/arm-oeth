// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/console.sol";

import {Script} from "forge-std/Script.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";

import {Mainnet} from "contracts/utils/Addresses.sol";
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";

abstract contract AbstractDeployScript is Script {
    using GovSixHelper for GovProposal;

    address deployer;
    uint256 public deployBlockNum = type(uint256).max;

    // DeployerRecord stuff to be extracted as well
    struct DeployRecord {
        string name;
        address addr;
    }

    DeployRecord[] public deploys;

    mapping(string => address) public deployedContracts;

    function _recordDeploy(string memory name, address addr) internal {
        deploys.push(DeployRecord({name: name, addr: addr}));
        console.log(string(abi.encodePacked("> Deployed ", name, " at")), addr);
        deployedContracts[name] = addr;
    }
    // End DeployRecord

    function getAllDeployRecords() external view returns (DeployRecord[] memory) {
        return deploys;
    }

    function preloadDeployedContract(string memory name, address addr) external {
        deployedContracts[name] = addr;
    }

    function isForked() public view returns (bool) {
        return vm.isContext(VmSafe.ForgeContext.ScriptDryRun) || vm.isContext(VmSafe.ForgeContext.TestGroup);
    }

    function setUp() external virtual {}

    function run() external {
        // Will not execute script if after this block number
        if (block.number > deployBlockNum) {
            // console.log("Current block %s, script block %s", block.number, deployBlockNum);
            return;
        }

        if (this.isForked()) {
            deployer = Mainnet.INITIAL_DEPLOYER;
            console.log("Running script on mainnet fork impersonating: %s", deployer);
            vm.startPrank(deployer);
        } else {
            uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            deployer = vm.rememberKey(deployerPrivateKey);
            vm.startBroadcast(deployer);
            console.log("Deploying on mainnet with deployer: %s", deployer);
        }

        _execute();

        if (this.isForked()) {
            vm.stopPrank();
            _buildGovernanceProposal();
            _fork();
        } else {
            vm.stopBroadcast();
        }
    }

    function DEPLOY_NAME() external view virtual returns (string memory);

    function proposalExecuted() external view virtual returns (bool);

    function skip() external view virtual returns (bool) {
        return false;
    }

    function _execute() internal virtual;

    function _fork() internal virtual {}

    function _buildGovernanceProposal() internal virtual {}

    function handleGovernanceProposal() external virtual {
        if (this.proposalExecuted()) {
            return;
        }

        _buildGovernanceProposal();
        // _fork();
    }
}
