// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MorphoMarket} from "contracts/markets/MorphoMarket.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $010_UpgradeLidoARMAssetScript is AbstractDeployScript("010_UpgradeLidoARMAssetScript") {
    using GovHelper for GovProposal;

    function _execute() internal override {
        // 1. Deploy new Lido implementation
        uint256 claimDelay = 10 minutes;
        LidoARM lidoARMImpl = new LidoARM(Mainnet.STETH, Mainnet.WETH, Mainnet.LIDO_WITHDRAWAL, claimDelay, 1e7, 1e18);
        _recordDeployment("LIDO_ARM_IMPL", address(lidoARMImpl));

        // 2. Deploy new MorphoMarket implementation
        MorphoMarket morphoMarket = new MorphoMarket(Mainnet.LIDO_ARM, Mainnet.MORPHO_MARKET_MEVCAPITAL);
        _recordDeployment("MORPHO_MARKET_MEVCAPITAL_IMP", address(morphoMarket));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Update Lido ARM to add asset() view function");

        // 1. Upgrade LidoARM to new implementation
        govProposal.action(
            resolver.implementations("LIDO_ARM"),
            "upgradeTo(address)",
            abi.encode(resolver.implementations("LIDO_ARM_IMPL"))
        );

        // 2. Upgrade MorphoMarket to new implementation
        govProposal.action(
            resolver.implementations("MORPHO_MARKET_MEVCAPITAL"),
            "upgradeTo(address)",
            abi.encode(resolver.implementations("MORPHO_MARKET_MEVCAPITAL_IMP"))
        );

        // 3. Set the MerkleDistributor address in the MorphoMarket
        govProposal.action(
            resolver.implementations("MORPHO_MARKET_MEVCAPITAL"),
            "setMerkleDistributor(address)",
            abi.encode(Mainnet.MERKLE_DISTRIBUTOR)
        );
    }
}
