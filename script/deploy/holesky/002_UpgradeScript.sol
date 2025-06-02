// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {OethARM} from "contracts/OethARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Holesky} from "contracts/utils/Addresses.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract UpgradeHoleskyScript is AbstractDeployScript {
    string public constant override DEPLOY_NAME = "002_UpgradeHolesky";
    bool public constant override proposalExecuted = false;

    address newImpl;
    Proxy internal proxy;

    constructor(address _proxy) {
        proxy = Proxy(payable(_proxy));
    }

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy new implementation
        newImpl = address(new OethARM(Holesky.OETH, Holesky.WETH, Holesky.OETH_VAULT));
        _recordDeploy("OETH_ARM_IMPL", newImpl);
    }

    function _fork() internal override {
        // Upgrade the proxy
        vm.prank(Holesky.RELAYER);
        proxy.upgradeTo(newImpl);
    }
}
