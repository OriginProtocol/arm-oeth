// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Deployment
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

contract $021_UpgradeEtherFiARMCrossPriceScript is AbstractDeployScript("021_UpgradeEtherFiARMCrossPriceScript") {
    using GovHelper for GovProposal;

    function _execute() internal override {}

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Update EtherFi ARM cross price");
        govProposal.action(
            resolver.resolve("ETHER_FI_ARM"), "setCrossPrice(address,uint256)", abi.encode(Mainnet.EETH, 0.99996e36)
        );
    }
}
