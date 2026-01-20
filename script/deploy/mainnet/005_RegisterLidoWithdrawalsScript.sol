// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract imports
import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment imports
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract RegisterLidoWithdrawalsScript is AbstractDeployScript("005_RegisterLidoWithdrawalsScript") {
    using GovHelper for GovProposal;

    bool public override skip = false;
    bool public constant override proposalExecuted = true;

    LidoARM lidoARMImpl;

    function _execute() internal override {
        // 1. Deploy new Lido ARM implementation
        uint256 claimDelay = 10 minutes;
        lidoARMImpl = new LidoARM(Mainnet.STETH, Mainnet.WETH, Mainnet.LIDO_WITHDRAWAL, claimDelay, 0, 0);
        _recordDeployment("LIDO_ARM_IMPL", address(lidoARMImpl));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Upgrade Lido ARM and register Lido withdrawal requests");

        bytes memory callData = abi.encodeWithSignature("registerLidoWithdrawalRequests()");

        bytes memory proxyData = abi.encode(resolver.implementations("LIDO_ARM_IMPL"), callData);

        govProposal.action(resolver.implementations("LIDO_ARM"), "upgradeToAndCall(address,bytes)", proxyData);
    }
}
