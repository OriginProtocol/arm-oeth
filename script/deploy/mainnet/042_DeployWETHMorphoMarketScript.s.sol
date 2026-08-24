// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MultiAssetARM} from "contracts/MultiAssetARM.sol";
import {MetaMorphoV1_1Market} from "contracts/markets/MetaMorphoV1_1Market.sol";
import {Abstract4626MarketWrapper} from "contracts/markets/Abstract4626MarketWrapper.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

/// @title Deploy the WETH ARM Morpho market
/// @notice Deploys a MetaMorpho V1.1 wrapper for the WETH ARM using the same Morpho vault as the
///         LidoARM and EtherFiARM wrappers. The mainnet 2/8 multisig owns the wrapper and acts as
///         its harvester. It also adds and activates the wrapper on the WETH ARM.
/// @dev The multisig actions are simulated in _fork(); on mainnet they are executed separately by
///      the multisig after the proxy and implementation have been deployed.
contract $042_DeployWETHMorphoMarketScript is AbstractDeployScript("042_DeployWETHMorphoMarketScript") {
    function _execute() internal override {
        address wethARM = resolver.resolve("WETH_ARM");

        // 1. Deploy the MorphoMarket proxy.
        Proxy morphoMarketProxy = new Proxy();
        _recordDeployment("MORPHO_MARKET_WETH_ARM", address(morphoMarketProxy));

        // 2. Deploy the implementation for the WETH ARM and the shared Morpho vault.
        MetaMorphoV1_1Market morphoMarketImpl = new MetaMorphoV1_1Market(wethARM, Mainnet.MORPHO_WETH_VAULT);
        _recordDeployment("MORPHO_MARKET_WETH_ARM_IMPL", address(morphoMarketImpl));

        // 3. Initialize the wrapper and hand ownership to the WETH ARM's 2/8 multisig.
        bytes memory data = abi.encodeWithSelector(
            Abstract4626MarketWrapper.initialize.selector, Mainnet.MULTISIG_2_OF_8, Mainnet.MERKLE_DISTRIBUTOR
        );
        morphoMarketProxy.initialize(address(morphoMarketImpl), Mainnet.MULTISIG_2_OF_8, data);
    }

    function _fork() internal override {
        MultiAssetARM wethARM = MultiAssetARM(payable(resolver.resolve("WETH_ARM")));
        address morphoMarket = resolver.resolve("MORPHO_MARKET_WETH_ARM");

        // Idempotent: the deployment runner can replay pending multisig actions on forks.
        if (!wethARM.supportedMarkets(morphoMarket)) {
            address[] memory markets = new address[](1);
            markets[0] = morphoMarket;

            vm.prank(Mainnet.MULTISIG_2_OF_8);
            wethARM.addMarkets(markets);
        }

        if (wethARM.activeMarket() != morphoMarket) {
            vm.prank(Mainnet.MULTISIG_2_OF_8);
            wethARM.setActiveMarket(morphoMarket);
        }
    }
}
