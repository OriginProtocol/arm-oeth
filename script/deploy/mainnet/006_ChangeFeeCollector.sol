// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract imports
import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment imports
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract ChangeFeeCollectorScript is AbstractDeployScript("006_ChangeFeeCollector") {
    using GovHelper for GovProposal;

    bool public override skip = false;
    bool public constant override proposalExecuted = true;

    LidoARM lidoARMImpl;

    function _execute() internal override {}

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Change fee collector");

        govProposal.action(
            resolver.implementations("LIDO_ARM"), "setFeeCollector(address)", abi.encode(Mainnet.BUYBACK_OPERATOR)
        );
    }
}
