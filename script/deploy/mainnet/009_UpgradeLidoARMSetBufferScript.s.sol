// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $009_UpgradeLidoARMSetBufferScript is AbstractDeployScript("009_UpgradeLidoARMSetBufferScript") {
    using GovHelper for GovProposal;

    function _execute() internal override {
        // 1. Deploy new Lido implementation
        uint256 claimDelay = 10 minutes;
        LidoARM lidoARMImpl = new LidoARM(Mainnet.STETH, Mainnet.WETH, Mainnet.LIDO_WITHDRAWAL, claimDelay, 1e7, 1e18);
        _recordDeployment("LIDO_ARM_IMPL", address(lidoARMImpl));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Update Lido ARM to allow operator to setBuffer()");

        govProposal.action(
            resolver.resolve("LIDO_ARM"), "upgradeTo(address)", abi.encode(resolver.resolve("LIDO_ARM_IMPL"))
        );

        govProposal.action(resolver.resolve("LIDO_ARM"), "setCapManager(address)", abi.encode(address(0)));
    }
}
