// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/console.sol";

import {Script} from "forge-std/Script.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";

import {AddressResolver} from "contracts/utils/Addresses.sol";
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";

abstract contract AbstractDeployScript is Script {
    using GovSixHelper for GovProposal;

    address deployer;
    uint256 public deployBlockNum = type(uint256).max;

    bool public tenderlyTestnet;

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
        return tenderlyTestnet || vm.isContext(VmSafe.ForgeContext.ScriptDryRun)
            || vm.isContext(VmSafe.ForgeContext.TestGroup);
    }

    /// @notice Detect if the RPC URL is a tenderly testnet, by trying to call a specific tenderly method on rpc.
    /// @dev if the call success, it means we are on a tenderly testnet, otherwise we arn't.
    function isTenderlyRpc() public returns (bool) {
        // Try to give ethers to "ARM_MULTISIG"
        try vm.rpc("tenderly_setBalance", "[[\"0xC8F2cF4742C86295653f893214725813B16f7410\"], \"0xDE0B6B3A7640000\"]") {
            tenderlyTestnet = true;
            return true;
        } catch {
            return false;
        }
    }

    function setUp() external virtual {
        isTenderlyRpc();
    }

    function run() external {
        // Will not execute script if after this block number
        if (block.number > deployBlockNum) {
            // console.log("Current block %s, script block %s", block.number, deployBlockNum);
            return;
        }

        if (this.isForked()) {
            AddressResolver resolver = new AddressResolver();
            deployer = resolver.resolve("DEPLOYER");
            if (tenderlyTestnet) {
                // Give enough ethers to deployer
                vm.rpc(
                    "tenderly_setBalance", "[[\"0x0000000000000000000000000000000000001001\"], \"0xDE0B6B3A7640000\"]"
                );
                console.log("Deploying on Tenderly testnet with deployer: %s", deployer);
                vm.startBroadcast(deployer);
            } else {
                console.log("Running script on mainnet fork impersonating: %s", deployer);
                vm.startPrank(deployer);
            }
        } else {
            uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            deployer = vm.rememberKey(deployerPrivateKey);
            vm.startBroadcast(deployer);
            console.log("Deploying on mainnet with deployer: %s", deployer);
        }

        _execute();

        if (this.isForked()) {
            if (tenderlyTestnet) {
                _buildGovernanceProposal();
                vm.stopBroadcast();
                _fork();
            } else {
                vm.stopPrank();
                _buildGovernanceProposal();
                _fork();
            }
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
