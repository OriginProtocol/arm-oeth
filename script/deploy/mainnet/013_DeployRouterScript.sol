// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry imports
import {console} from "forge-std/console.sol";

// Contract imports
import {ARMRouter} from "contracts/ARMRouter.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment imports
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract DeployRouterScript is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "013_DeployRouterScript";
    bool public constant override proposalExecuted = false;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy ARM Router
        _recordDeploy("ARM_ROUTER", address(new ARMRouter(Mainnet.WETH)));

        console.log("Finished deploying", DEPLOY_NAME);
    }
}
