// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {EthenaAssetAdapter} from "contracts/adapters/EthenaAssetAdapter.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $044_UpgradeEthenaAssetAdapterScript is AbstractDeployScript("044_UpgradeEthenaAssetAdapterScript") {
    using GovHelper for GovProposal;

    function _execute() internal override {
        EthenaAssetAdapter impl = new EthenaAssetAdapter(resolver.resolve("ETHENA_ARM"), Mainnet.USDE, Mainnet.SUSDE);
        _recordDeployment("ETHENA_ARM_SUSDE_ADAPTER_IMPL", address(impl));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Support Ethena redemptions with and without a cooldown");
        govProposal.action(
            resolver.resolve("ETHENA_ARM_SUSDE_ADAPTER"),
            "upgradeTo(address)",
            abi.encode(resolver.resolve("ETHENA_ARM_SUSDE_ADAPTER_IMPL"))
        );
    }
}
