// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $040_UnpauseEtherFi is AbstractDeployScript("040_UnpauseEtherFi") {
    using GovHelper for GovProposal;

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Unpause EtherFi ARM");
        govProposal.action(resolver.resolve("ETHER_FI_ARM"), "unpause()", "");
    }
}
