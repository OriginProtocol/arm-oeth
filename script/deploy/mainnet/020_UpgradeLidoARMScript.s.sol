// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $020_UpgradeLidoARMScript is AbstractDeployScript("020_UpgradeLidoARMScript") {
    using GovHelper for GovProposal;

    function _execute() internal override {
        // 1. Deploy new LidoARM implementation
        uint256 claimDelay = 10 minutes;
        uint256 minSharesToRedeem = 1e7;
        int256 allocateThreshold = 1e18;
        LidoARM lidoARMImpl =
            new LidoARM(Mainnet.STETH, Mainnet.WETH, Mainnet.LIDO_WITHDRAWAL, claimDelay, minSharesToRedeem, allocateThreshold);
        _recordDeployment("LIDO_ARM_IMPL", address(lidoARMImpl));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Upgrade Lido ARM to restrict deposits during insolvency");

        govProposal.action(
            resolver.resolve("LIDO_ARM"), "upgradeTo(address)", abi.encode(resolver.resolve("LIDO_ARM_IMPL"))
        );
    }
}
