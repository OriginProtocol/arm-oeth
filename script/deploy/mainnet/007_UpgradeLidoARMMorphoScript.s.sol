// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {Proxy} from "contracts/Proxy.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MorphoMarket} from "contracts/markets/MorphoMarket.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $007_UpgradeLidoARMMorphoScript is AbstractDeployScript("007_UpgradeLidoARMMorphoScript") {
    using GovHelper for GovProposal;

    function _execute() internal override {
        // 1. Deploy new Lido implementation
        uint256 claimDelay = 10 minutes;
        LidoARM lidoARMImpl = new LidoARM(Mainnet.STETH, Mainnet.WETH, Mainnet.LIDO_WITHDRAWAL, claimDelay, 1e7, 1e18);
        _recordDeployment("LIDO_ARM_IMPL", address(lidoARMImpl));

        // 2. Deploy MorphoMarket proxy
        Proxy morphoMarketProxy = new Proxy();
        _recordDeployment("MORPHO_MARKET_MEVCAPITAL", address(morphoMarketProxy));

        // 3. Deploy MorphoMarket
        MorphoMarket morphoMarket = new MorphoMarket(Mainnet.LIDO_ARM, Mainnet.MORPHO_MARKET_MEVCAPITAL);
        _recordDeployment("MORPHO_MARKET_MEVCAPITAL_IMP", address(morphoMarket));

        // 4. Initialize MorphoMarket proxy with the implementation
        bytes memory data = abi.encodeWithSignature("initialize(address)", Mainnet.STRATEGIST);
        morphoMarketProxy.initialize(address(morphoMarket), Mainnet.TIMELOCK, data);
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Update Lido ARM to Morpho Market");

        govProposal.action(
            resolver.resolve("LIDO_ARM"), "upgradeTo(address)", abi.encode(resolver.resolve("LIDO_ARM_IMPL"))
        );

        address[] memory markets = new address[](1);
        markets[0] = resolver.resolve("MORPHO_MARKET_MEVCAPITAL");
        govProposal.action(resolver.resolve("LIDO_ARM"), "addMarkets(address[])", abi.encode(markets));

        govProposal.action(
            resolver.resolve("LIDO_ARM"),
            "setActiveMarket(address)",
            abi.encode(resolver.resolve("MORPHO_MARKET_MEVCAPITAL"))
        );

        govProposal.action(
            resolver.resolve("LIDO_ARM"),
            "setARMBuffer(uint256)",
            abi.encode(0.2e18) // 20% buffer
        );
    }
}
