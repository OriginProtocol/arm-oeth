// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract ChangeFeeCollectorScript is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "006_ChangeFeeCollector";
    bool public constant override proposalExecuted = false;

    LidoARM lidoARMImpl;

    function _execute() internal override {}

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Change fee collector");

        govProposal.action(
            deployedContracts["LIDO_ARM"], "setFeeCollector(address)", abi.encode(Mainnet.BUYBACK_OPERATOR)
        );
    }

    function _fork() internal override {
        if (this.isForked()) {
            govProposal.simulate();
        }
    }
}
