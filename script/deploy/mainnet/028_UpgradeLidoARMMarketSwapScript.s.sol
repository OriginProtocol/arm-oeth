// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $028_UpgradeLidoARMMarketSwapScript is AbstractDeployScript("028_UpgradeLidoARMMarketSwapScript") {
    using GovHelper for GovProposal;

    function _execute() internal override {
        uint256 claimDelay = 10 minutes;
        uint256 minSharesToRedeem = 1e7;
        LidoARM lidoARMImpl = new LidoARM(
            Mainnet.STETH, Mainnet.WETH, Mainnet.LIDO_WITHDRAWAL, claimDelay, minSharesToRedeem
        );
        _recordDeployment("LIDO_ARM_IMPL", address(lidoARMImpl));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Upgrade Lido ARM to add operator market swaps");

        govProposal.action(
            resolver.resolve("LIDO_ARM"), "upgradeTo(address)", abi.encode(resolver.resolve("LIDO_ARM_IMPL"))
        );
    }
}
