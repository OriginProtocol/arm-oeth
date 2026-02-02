// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $006_ChangeFeeCollector is AbstractDeployScript("006_ChangeFeeCollector") {
    using GovHelper for GovProposal;

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Change fee collector");

        govProposal.action(
            resolver.implementations("LIDO_ARM"), "setFeeCollector(address)", abi.encode(Mainnet.BUYBACK_OPERATOR)
        );
    }
}
