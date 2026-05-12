// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {LidoARM} from "contracts/LidoARM.sol";
import {StETHAssetAdapter} from "contracts/adapters/StETHAssetAdapter.sol";
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

        StETHAssetAdapter stethAdapter =
            new StETHAssetAdapter(Mainnet.LIDO_ARM, Mainnet.WETH, Mainnet.STETH, Mainnet.LIDO_WITHDRAWAL);
        _recordDeployment("LIDO_ARM_STETH_ADAPTER", address(stethAdapter));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Upgrade Lido ARM and add stETH asset adapter");

        bytes memory proxyData = abi.encode(resolver.resolve("LIDO_ARM_IMPL"), "");

        govProposal.action(resolver.resolve("LIDO_ARM"), "upgradeToAndCall(address,bytes)", proxyData);
        govProposal.action(
            resolver.resolve("LIDO_ARM"),
            "addBaseAsset(address,address,uint256,uint256,uint256,uint256,uint256,bool)",
            abi.encode(
                Mainnet.STETH,
                resolver.resolve("LIDO_ARM_STETH_ADAPTER"),
                0.99975e36,
                0.9999e36,
                type(uint256).max,
                type(uint256).max,
                0.9998e36,
                true
            )
        );
    }
}
