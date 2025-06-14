// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {OethARM} from "contracts/OethARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract UpgradeMainnetScript is AbstractDeployScript {
    string public constant override DEPLOY_NAME = "002_UpgradeMainnet";
    bool public constant override proposalExecuted = true;

    address newImpl;
    Proxy internal proxy;

    constructor(address _proxy) {
        proxy = Proxy(payable(_proxy));
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
        vm.prank(Mainnet.TIMELOCK);
        proxy.upgradeTo(newImpl);
        console.log("OethARM upgraded");
    }
}
