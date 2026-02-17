// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {Proxy} from "contracts/Proxy.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {MorphoMarket} from "contracts/markets/MorphoMarket.sol";
import {Abstract4626MarketWrapper} from "contracts/markets/Abstract4626MarketWrapper.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $013_UpgradeOETHARMScript is AbstractDeployScript("013_UpgradeOETHARMScript") {
    using GovHelper for GovProposal;

    function _execute() internal override {
        // 1. Deploy new Origin implementation
        uint256 claimDelay = 10 minutes;
        OriginARM originARMImpl = new OriginARM(Mainnet.OETH, Mainnet.WETH, Mainnet.OETH_VAULT, claimDelay, 1e7, 1e18);
        _recordDeployment("OETH_ARM_IMPL", address(originARMImpl));

        // 2. Deploy MorphoMarket proxy
        Proxy morphoMarketProxy = new Proxy();
        _recordDeployment("MORPHO_MARKET_ORIGIN", address(morphoMarketProxy));

        // 3. Deploy MorphoMarket
        MorphoMarket morphoMarket = new MorphoMarket(Mainnet.OETH_ARM, Mainnet.MORPHO_MARKET_YEARN_OG);
        _recordDeployment("MORPHO_MARKET_ORIGIN_IMPL", address(morphoMarket));
        // 4. Initialize MorphoMarket proxy with the implementation, Timelock as owner
        bytes memory data = abi.encodeWithSelector(
            Abstract4626MarketWrapper.initialize.selector, Mainnet.STRATEGIST, Mainnet.MERKLE_DISTRIBUTOR
        );
        morphoMarketProxy.initialize(address(morphoMarket), Mainnet.TIMELOCK, data);
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Update OETH ARM to use Origin ARM contract");

        // 1. Transfer OETH out of the existing OETH ARM, to have a clean assets per share ratio.
        uint256 balanceOETH = IERC20(Mainnet.OETH).balanceOf(resolver.implementations("OETH_ARM"));
        govProposal.action(
            resolver.implementations("OETH_ARM"),
            "transferToken(address,address,uint256)",
            abi.encode(Mainnet.OETH, Mainnet.TREASURY_LP, balanceOETH)
        );

        // 2. Transfer WETH out of the existing OETH ARM, to have a clean assets per share ratio.
        uint256 balanceWETH = IERC20(Mainnet.WETH).balanceOf(resolver.implementations("OETH_ARM"));
        govProposal.action(
            resolver.implementations("OETH_ARM"),
            "transferToken(address,address,uint256)",
            abi.encode(Mainnet.WETH, Mainnet.TREASURY_LP, balanceWETH)
        );

        // 3. Timelock needs to approve the OETH ARM to pull WETH for initialization.
        govProposal.action(
            Mainnet.WETH, "approve(address,uint256)", abi.encode(resolver.implementations("OETH_ARM"), 1e12)
        );

        // 4. Upgrade the OETH ARM implementation, and initialize.
        bytes memory initializeData = abi.encodeWithSelector(
            OriginARM.initialize.selector,
            "Origin ARM",
            "ARM-WETH-OETH",
            Mainnet.ARM_RELAYER,
            2000, // 20% performance fee
            Mainnet.BUYBACK_OPERATOR, // Fee collector
            address(0)
        );

        // 5. Upgrade OETH ARM to OriginARM and call initialize
        govProposal.action(
            resolver.implementations("OETH_ARM"),
            "upgradeToAndCall(address,bytes)",
            abi.encode(resolver.implementations("OETH_ARM_IMPL"), initializeData)
        );

        // 6. Add Morpho Market as an active market
        address[] memory markets = new address[](1);
        markets[0] = resolver.implementations("MORPHO_MARKET_ORIGIN");
        govProposal.action(resolver.implementations("OETH_ARM"), "addMarkets(address[])", abi.encode(markets));

        // 7. Set Morpho Market as the active market
        govProposal.action(
            resolver.implementations("OETH_ARM"),
            "setActiveMarket(address)",
            abi.encode(resolver.implementations("MORPHO_MARKET_ORIGIN"))
        );

        // 8. Set crossPrice to 0.9995 ETH
        uint256 crossPrice = 0.9995 * 1e36;
        govProposal.action(resolver.implementations("OETH_ARM"), "setCrossPrice(uint256)", abi.encode(crossPrice));
    }
}
