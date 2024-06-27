// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "./BaseMainnetScript.sol";
import {Vm} from "forge-std/Vm.sol";

import {Addresses} from "contracts/utils/Addresses.sol";

import {OEthARM} from "contracts/OEthARM.sol";
import {Proxy} from "contracts/Proxy.sol";

import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";

contract DeployCoreScript is BaseMainnetScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "000_DeployCoreScript";
    bool public constant override proposalExecuted = false;

    constructor() {}

    function _execute() internal override {
        console.log("Deploy:");
        console.log("------------");

        // 1. Deploy proxy contracts
        Proxy proxy = new Proxy();
        _recordDeploy("OETH_ARM", address(proxy));

        // 2. Deploy implementation
        OEthARM implementation = new OEthARM();
        _recordDeploy("OETH_ARM_IMPL", address(implementation));

        // 3. Initialize proxy
        proxy.initialize(address(implementation), Addresses.TIMELOCK, "");

        // // 4. Operator
        // proxy.setOperator(Addresses.STRATEGIST);
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Setup OETH ARM Contract");

        // NOTE: This could be done during deploy of proxy.
        // But doing this here to test governance flow.

        // Set operator
        govProposal.action(deployedContracts["OETH_ARM"], "setOperator(address)", abi.encode(Addresses.STRATEGIST));
    }

    function _fork() internal override {
        // Simulate on fork
        govProposal.simulate();
    }
}
