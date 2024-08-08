// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "./BaseMainnetScript.sol";
import {Vm} from "forge-std/Vm.sol";

import {Mainnet} from "contracts/utils/Addresses.sol";

import {OEthARM} from "contracts/OethARM.sol";
import {Proxy} from "contracts/Proxy.sol";

import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";

contract DeployCoreScript is BaseMainnetScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "001_DeployCoreScript";
    bool public constant override proposalExecuted = false;

    constructor() {}

    function _execute() internal override {
        console.log("Deploy:");
        console.log("------------");

        // 1. Deploy proxy contracts
        Proxy proxy = new Proxy();
        _recordDeploy("OETH_ARM", address(proxy));

        // 2. Deploy implementation
        OEthARM implementation = new OEthARM(Mainnet.OETH, Mainnet.WETH, Mainnet.OETH_VAULT);
        _recordDeploy("OETH_ARM_IMPL", address(implementation));

        // 3. Initialize proxy, set the owner and the operator
        bytes memory data = abi.encodeWithSignature("setOperator(address)", Mainnet.RELAYER);
        proxy.initialize(address(implementation), Mainnet.TIMELOCK, data);
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Setup OETH ARM Contract");

        // NOTE: This has already been done during deployment
        // but doing this here to test governance flow.

        // Set operator
        govProposal.action(deployedContracts["OETH_ARM"], "setOperator(address)", abi.encode(Mainnet.RELAYER));
    }

    function _fork() internal override {
        // Simulate on fork
        govProposal.simulate();
    }
}
