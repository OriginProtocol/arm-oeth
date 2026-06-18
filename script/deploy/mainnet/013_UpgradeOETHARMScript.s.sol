// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {Proxy} from "contracts/Proxy.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {OriginAssetAdapter} from "contracts/adapters/OriginAssetAdapter.sol";
import {WrappedOriginAssetAdapter} from "contracts/adapters/WrappedOriginAssetAdapter.sol";
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

        OriginAssetAdapter adapterImpl =
            new OriginAssetAdapter(Mainnet.OETH_ARM, Mainnet.OETH, Mainnet.WETH, Mainnet.OETH_VAULT);
        _recordDeployment("OETH_ARM_OETH_ADAPTER_IMPL", address(adapterImpl));
        Proxy adapterProxy = new Proxy();
        adapterProxy.initialize(address(adapterImpl), Mainnet.TIMELOCK, abi.encodeWithSignature("initialize()"));
        _recordDeployment("OETH_ARM_OETH_ADAPTER", address(adapterProxy));

        WrappedOriginAssetAdapter wrappedAdapterImpl = new WrappedOriginAssetAdapter(
            Mainnet.OETH_ARM, Mainnet.WOETH, Mainnet.OETH, Mainnet.WETH, Mainnet.OETH_VAULT
        );
        _recordDeployment("OETH_ARM_WOETH_ADAPTER_IMPL", address(wrappedAdapterImpl));
        Proxy wrappedAdapterProxy = new Proxy();
        wrappedAdapterProxy.initialize(
            address(wrappedAdapterImpl), Mainnet.TIMELOCK, abi.encodeWithSignature("initialize()")
        );
        _recordDeployment("OETH_ARM_WOETH_ADAPTER", address(wrappedAdapterProxy));

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
        uint256 balanceOETH = IERC20(Mainnet.OETH).balanceOf(resolver.resolve("OETH_ARM"));
        govProposal.action(
            resolver.resolve("OETH_ARM"),
            "transferToken(address,address,uint256)",
            abi.encode(Mainnet.OETH, Mainnet.TREASURY_LP, balanceOETH)
        );

        // 2. Transfer WETH out of the existing OETH ARM, to have a clean assets per share ratio.
        uint256 balanceWETH = IERC20(Mainnet.WETH).balanceOf(resolver.resolve("OETH_ARM"));
        govProposal.action(
            resolver.resolve("OETH_ARM"),
            "transferToken(address,address,uint256)",
            abi.encode(Mainnet.WETH, Mainnet.TREASURY_LP, balanceWETH)
        );

        // 3. Timelock needs to approve the OETH ARM to pull WETH for initialization.
        govProposal.action(Mainnet.WETH, "approve(address,uint256)", abi.encode(resolver.resolve("OETH_ARM"), 1e15));

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
            resolver.resolve("OETH_ARM"),
            "upgradeToAndCall(address,bytes)",
            abi.encode(resolver.resolve("OETH_ARM_IMPL"), initializeData)
        );

        // 6. Register OETH as the base asset.
        uint256 crossPrice = 0.9995 * 1e36;
        govProposal.action(
            resolver.resolve("OETH_ARM"),
            "addBaseAsset(address,address,uint256,uint256,uint256,uint256,uint256,bool)",
            abi.encode(
                Mainnet.OETH,
                resolver.resolve("OETH_ARM_OETH_ADAPTER"),
                0.9994 * 1e36,
                1e36,
                type(uint128).max,
                type(uint128).max,
                crossPrice,
                true
            )
        );

        // 7. Register wOETH as a non-pegged base asset.
        govProposal.action(
            resolver.resolve("OETH_ARM"),
            "addBaseAsset(address,address,uint256,uint256,uint256,uint256,uint256,bool)",
            abi.encode(
                Mainnet.WOETH,
                resolver.resolve("OETH_ARM_WOETH_ADAPTER"),
                0.9994 * 1e36,
                1e36,
                type(uint128).max,
                type(uint128).max,
                crossPrice,
                false
            )
        );

        // 8. Add Morpho Market as an active market
        address[] memory markets = new address[](1);
        markets[0] = resolver.resolve("MORPHO_MARKET_ORIGIN");
        govProposal.action(resolver.resolve("OETH_ARM"), "addMarkets(address[])", abi.encode(markets));

        // 9. Set Morpho Market as the active market
        govProposal.action(
            resolver.resolve("OETH_ARM"),
            "setActiveMarket(address)",
            abi.encode(resolver.resolve("MORPHO_MARKET_ORIGIN"))
        );
    }
}
