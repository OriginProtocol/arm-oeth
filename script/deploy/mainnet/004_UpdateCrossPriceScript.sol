// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Deployment imports
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract UpdateCrossPriceMainnetScript is AbstractDeployScript("004_UpdateCrossPriceScript") {
    using GovHelper for GovProposal;

    bool public override skip = false;
    bool public constant override proposalExecuted = true;

    function _execute() internal override {}

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Update Cross Price for Lido ARM");

        uint256 newCrossPrice = 0.9999 * 1e36;

        govProposal.action(resolver.implementations("LIDO_ARM"), "setCrossPrice(uint256)", abi.encode(newCrossPrice));
    }
}
