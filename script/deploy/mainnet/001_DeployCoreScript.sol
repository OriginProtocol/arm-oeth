// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import {Vm} from "forge-std/Vm.sol";

import "../AbstractDeployScript.sol";

import {OethARM} from "contracts/OethARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";

contract DeployCoreMainnetScript is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "001_CoreMainnet";
    bool public constant override proposalExecuted = false;

    constructor() {}

    function _execute() internal override {
        console.log("Deploy:");
        console.log("------------");

        // 1. Deploy proxy contracts
        Proxy proxy = new Proxy();
        _recordDeploy("OETH_ARM", address(proxy));

        // 2. Deploy implementation
        OethARM implementation = new OethARM(Mainnet.OETH, Mainnet.WETH, Mainnet.OETH_VAULT);
        _recordDeploy("OETH_ARM_IMPL", address(implementation));

        // 3. Initialize proxy, set the owner to TIMELOCK, set the operator to RELAYER and approve the OETH Vault to transfer OETH
        bytes memory data = abi.encodeWithSignature("initialize(address)", Mainnet.RELAYER);
        proxy.initialize(address(implementation), Mainnet.TIMELOCK, data);
    }

    function _buildGovernanceProposal() internal override {
        // govProposal.setDescription("Setup OETH ARM Contract");

        // NOTE: This has already been done during deployment
        // but doing this here to test governance flow.

        // Set operator
        // govProposal.action(deployedContracts["OETH_ARM"], "initialize(address)", abi.encode(Mainnet.RELAYER));
    }

    function _fork() internal override {
        // Simulate on fork
        // govProposal.simulate();
    }
}