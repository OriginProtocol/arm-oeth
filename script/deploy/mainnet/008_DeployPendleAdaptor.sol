// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract imports
import {PendleOriginARMSY} from "contracts/pendle/PendleOriginARMSY.sol";

// Deployment imports
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract DeployPendleAdaptor is AbstractDeployScript("008_DeployPendleAdaptor") {
    using GovHelper for GovProposal;

    bool public override skip = false;
    bool public constant override proposalExecuted = true;

    function _execute() internal override {
        // 1. Deploy PendleOriginARMSY
        PendleOriginARMSY sy =
            new PendleOriginARMSY("SY Lido ARM", "SY-ARM-WETH-stETH", resolver.implementations("LIDO_ARM"));
        _recordDeployment("PENDLE_ORIGIN_ARM_SY", address(sy));
    }

    function _buildGovernanceProposal() internal override {}
}
