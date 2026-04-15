// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Deployment
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

contract $016_UpgradeLidoARMCrossPriceScript is AbstractDeployScript("016_UpgradeLidoARMCrossPriceScript") {
    using GovHelper for GovProposal;

    function _execute() internal override {}

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Update Lido ARM cross price");
        govProposal.action(
            resolver.resolve("LIDO_ARM"), "setCrossPrice(address,uint256)", abi.encode(Mainnet.STETH, 0.99996e36)
        );
    }
}
