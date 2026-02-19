// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $005_RegisterLidoWithdrawalsScript is AbstractDeployScript("005_RegisterLidoWithdrawalsScript") {
    using GovHelper for GovProposal;

    function _execute() internal override {
        // 1. Deploy new Lido ARM implementation
        uint256 claimDelay = 10 minutes;
        LidoARM lidoARMImpl = new LidoARM(Mainnet.STETH, Mainnet.WETH, Mainnet.LIDO_WITHDRAWAL, claimDelay, 0, 0);
        _recordDeployment("LIDO_ARM_IMPL", address(lidoARMImpl));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Upgrade Lido ARM and register Lido withdrawal requests");

        bytes memory callData = abi.encodeWithSignature("registerLidoWithdrawalRequests()");

        bytes memory proxyData = abi.encode(resolver.resolve("LIDO_ARM_IMPL"), callData);

        govProposal.action(resolver.resolve("LIDO_ARM"), "upgradeToAndCall(address,bytes)", proxyData);
    }
}
