// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract imports
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MorphoMarket} from "contracts/markets/MorphoMarket.sol";
import {Abstract4626MarketWrapper} from "contracts/markets/Abstract4626MarketWrapper.sol";

// Deployment
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract $018_DeployNewMorphoMarketForLidoARM is AbstractDeployScript("018_DeployNewMorphoMarketForLidoARM") {
    using GovHelper for GovProposal;

    function _execute() internal override {
        // 1. Deploy MorphoMarket proxy
        Proxy morphoMarketProxy = new Proxy();
        _recordDeployment("MORPHO_MARKET_LIDO", address(morphoMarketProxy));

        // 2. Deploy MorphoMarket
        MorphoMarket morphoMarket = new MorphoMarket(Mainnet.LIDO_ARM, Mainnet.MORPHO_MARKET_OETH_VAULT);
        _recordDeployment("MORPHO_MARKET_LIDO_IMPL", address(morphoMarket));

        // 3. Initialize MorphoMarket proxy with the implementation, Timelock as owner
        bytes memory data = abi.encodeWithSelector(
            Abstract4626MarketWrapper.initialize.selector, Mainnet.STRATEGIST, Mainnet.MERKLE_DISTRIBUTOR
        );
        morphoMarketProxy.initialize(address(morphoMarket), Mainnet.TIMELOCK, data);
    }

    function _buildGovernanceProposal() internal override {
        // 1. Set governance proposal description
        govProposal.setDescription("Change Lido ARM MorphoMarket");

        // 2. Add the new MorphoMarket to the Lido ARM
        address[] memory marketsToAdd = new address[](1);
        marketsToAdd[0] = resolver.implementations("MORPHO_MARKET_LIDO");
        govProposal.action(resolver.implementations("LIDO_ARM"), "addMarkets(address[])", abi.encode(marketsToAdd));

        // 3. Set the new MorphoMarket as the active market for the Lido ARM
        govProposal.action(
            resolver.implementations("LIDO_ARM"),
            "setActiveMarket(address)",
            abi.encode(resolver.implementations("MORPHO_MARKET_LIDO"))
        );

        // 4. Remove the old MorphoMarket from the Lido ARM
        govProposal.action(
            resolver.implementations("LIDO_ARM"),
            "removeMarket(address)",
            abi.encode(resolver.implementations("MORPHO_MARKET_MEVCAPITAL"))
        );
    }
}
