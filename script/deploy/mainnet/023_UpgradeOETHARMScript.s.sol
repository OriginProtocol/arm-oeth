// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {OriginARM} from "contracts/OriginARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $023_UpgradeOETHARMScript is AbstractDeployScript("023_UpgradeOETHARMScript") {
    using GovHelper for GovProposal;

    function _execute() internal override {
        // 1. Deploy new OriginARM implementation
        uint256 claimDelay = 10 minutes;
        uint256 minSharesToRedeem = 1e7;
        int256 allocateThreshold = 1e18;
        OriginARM originARMImpl =
            new OriginARM(Mainnet.OETH, Mainnet.WETH, Mainnet.OETH_VAULT, claimDelay, minSharesToRedeem, allocateThreshold);
        _recordDeployment("OETH_ARM_IMPL", address(originARMImpl));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Upgrade OETH ARM to restrict deposits during insolvency");

        govProposal.action(
            resolver.resolve("OETH_ARM"), "upgradeTo(address)", abi.encode(resolver.resolve("OETH_ARM_IMPL"))
        );
    }
}
