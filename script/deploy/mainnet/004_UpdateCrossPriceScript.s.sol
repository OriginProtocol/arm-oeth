// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $004_UpdateCrossPriceMainnetScript is AbstractDeployScript("004_UpdateCrossPriceScript") {
    using GovHelper for GovProposal;

    bool public override proposalExecuted = true;

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Update Cross Price for Lido ARM");

        uint256 newCrossPrice = 0.9999 * 1e36;

        govProposal.action(resolver.implementations("LIDO_ARM"), "setCrossPrice(uint256)", abi.encode(newCrossPrice));
    }
}
