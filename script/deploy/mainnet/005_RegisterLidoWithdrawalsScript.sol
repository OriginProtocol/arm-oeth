// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract RegisterLidoWithdrawalsScript is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "005_RegisterLidoWithdrawalsScript";
    bool public constant override proposalExecuted = false;

    LidoARM lidoARMImpl;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy new Lido ARM implementation
        uint256 claimDelay = tenderlyTestnet ? 1 minutes : 10 minutes;
        lidoARMImpl = new LidoARM(Mainnet.STETH, Mainnet.WETH, Mainnet.LIDO_WITHDRAWAL, claimDelay);
        _recordDeploy("LIDO_ARM_IMPL", address(lidoARMImpl));

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Upgrade Lido ARM and register Lido withdrawal requests");

        bytes memory callData = abi.encodeWithSignature("registerLidoWithdrawalRequests()");
        console.log("registerLidoWithdrawalRequests data:");
        console.logBytes(callData);

        bytes memory proxyData = abi.encode(address(lidoARMImpl), callData);
        console.log("proxy upgradeToAndCall encoded params:");
        console.logBytes(proxyData);

        govProposal.action(deployedContracts["LIDO_ARM"], "upgradeToAndCall(address,bytes)", proxyData);

        _fork();
    }

    function _fork() internal override {
        if (this.isForked()) {
            govProposal.simulate();
        }
    }
}
