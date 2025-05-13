// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {Proxy} from "contracts/Proxy.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract DeployOriginARMProxyScript is AbstractDeployScript {
    string public constant override DEPLOY_NAME = "001_DeployOriginARMProxyScript";
    bool public constant override proposalExecuted = false;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy proxy for the Origin ARM
        Proxy originARMProxy = new Proxy();
        _recordDeploy("ORIGIN_ARM", address(originARMProxy));

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _buildGovernanceProposal() internal override {}

    function _fork() internal view override {
        if (this.isForked()) {}
    }
}
