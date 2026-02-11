// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry imports
import {console} from "forge-std/console.sol";

// Contract imports
import {PendleOriginARMSY} from "contracts/pendle/PendleOriginARMSY.sol";

// Deployment imports
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract DeployPendleAdaptorEtherFi is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "019_DeployPendleAdaptor_EtherFi";
    bool public constant override proposalExecuted = false;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy PendleOriginARMSY
        PendleOriginARMSY sy =
            new PendleOriginARMSY("SY EtherFi ARM", "SY-ARM-WETH-eETH", deployedContracts["ETHER_FI_ARM"]);
        _recordDeploy("PENDLE_ETHERFI_ARM_SY", address(sy));

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _buildGovernanceProposal() internal override {}
}
