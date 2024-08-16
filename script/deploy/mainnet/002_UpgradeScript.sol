// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {OethARM} from "contracts/OethARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";
import {DeployManager} from "../DeployManager.sol";

contract UpgradeMainnetScript is AbstractDeployScript {
    string public constant override DEPLOY_NAME = "002_UpgradeMainnet";
    bool public constant override proposalExecuted = false;

    address newImpl;
    DeployManager internal deployManager;

    constructor(DeployManager _deployManager) {
        deployManager = _deployManager;
    }

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy new implementation
        newImpl = address(new OethARM(Mainnet.OETH, Mainnet.WETH, Mainnet.OETH_VAULT));
        _recordDeploy("OETH_ARM_IMPL", newImpl);
    }

    function _fork() internal override {
        // Upgrade the proxy
        Proxy proxy = Proxy(deployManager.getDeployment("OETH_ARM"));

        vm.prank(Mainnet.TIMELOCK);
        proxy.upgradeTo(newImpl);
        console.log("OethARM upgraded");
    }
}
