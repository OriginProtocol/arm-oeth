// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

// Contracts
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MetaMorphoV1_1Market} from "contracts/markets/MetaMorphoV1_1Market.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

/// @title Upgrade the Lido ARM Morpho market
/// @notice Deploys loss-aware MetaMorpho V1.1 wrapper logic and upgrades the existing Lido ARM
///         MorphoMarket proxy through governance. The proxy address and its storage are preserved.
contract $044_UpgradeLidoMorphoMarketScript is AbstractDeployScript("044_UpgradeLidoMorphoMarketScript") {
    using GovHelper for GovProposal;

    function _execute() internal override {
        MetaMorphoV1_1Market morphoMarketImpl =
            new MetaMorphoV1_1Market(resolver.resolve("LIDO_ARM"), Mainnet.MORPHO_WETH_VAULT);
        _recordDeployment("MORPHO_MARKET_LIDO_IMPL", address(morphoMarketImpl));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Upgrade the Lido ARM Morpho market to account for MetaMorpho lost assets");

        govProposal.action(
            resolver.resolve("MORPHO_MARKET_LIDO"),
            "upgradeTo(address)",
            abi.encode(resolver.resolve("MORPHO_MARKET_LIDO_IMPL"))
        );
    }
}
