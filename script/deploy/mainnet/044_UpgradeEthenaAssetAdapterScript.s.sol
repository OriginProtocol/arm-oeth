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
        govProposal.setDescription("Upgrade Ethena redemptions and set the sUSDe cross price to parity");
        govProposal.action(
            resolver.resolve("ETHENA_ARM_SUSDE_ADAPTER"),
            "upgradeToAndCall(address,bytes)",
            abi.encode(
                resolver.resolve("ETHENA_ARM_SUSDE_ADAPTER_IMPL"),
                abi.encodeCall(EthenaAssetAdapter.checkQueueEmpty, ())
            )
        );
        // Before execution, the operator must keep the normalized sell price at or above parity.
        govProposal.action(
            resolver.resolve("ETHENA_ARM"), "setCrossPrice(address,uint256)", abi.encode(Mainnet.SUSDE, 1e36)
        );
    }
}
