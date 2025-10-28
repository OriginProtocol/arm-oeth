// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "forge-std/console.sol";

// Contract imports
import {PendleOriginARMSY} from "contracts/pendle/PendleOriginARMSY.sol";

// Deployment imports
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract DeployPendleAdaptorSonic is AbstractDeployScript {
    string public constant override DEPLOY_NAME = "004_DeployPendleAdaptor";
    bool public constant override proposalExecuted = false;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy PendleOriginARMSY
        //PendleOriginARMSY sy = new PendleOriginARMSY("SY ORIGIN ARM", "SY-ARM-WS-OS", deployedContracts["ORIGIN_ARM"]);
        //_recordDeploy("PENDLE_ORIGIN_ARM_SY", address(sy));

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _buildGovernanceProposal() internal override {}
}
