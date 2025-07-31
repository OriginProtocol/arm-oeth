// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract UpdateCrossPriceMainnetScript is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "004_UpdateCrossPriceScript";
    bool public constant override proposalExecuted = true;

    function _execute() internal override {}

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Update Cross Price for Lido ARM");

        uint256 newCrossPrice = 0.9999 * 1e36;

        govProposal.action(deployedContracts["LIDO_ARM"], "setCrossPrice(uint256)", abi.encode(newCrossPrice));

        _fork();
    }

    function _fork() internal override {
        if (this.isForked()) {
            govProposal.simulate();
        }
    }
}
