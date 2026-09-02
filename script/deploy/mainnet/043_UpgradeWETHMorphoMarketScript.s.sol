// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MetaMorphoV1_1Market} from "contracts/markets/MetaMorphoV1_1Market.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

/// @title Upgrade the WETH ARM Morpho market
/// @notice Deploys loss-aware MetaMorpho V1.1 wrapper logic and upgrades the existing WETH ARM
///         MorphoMarket proxy. The proxy address and its storage are preserved.
/// @dev The proxy is owned by the mainnet 5/8 multisig. The multisig upgrade is simulated in
///      `_fork()` and must be executed separately after the implementation is deployed on mainnet.
contract $043_UpgradeWETHMorphoMarketScript is AbstractDeployScript("043_UpgradeWETHMorphoMarketScript") {
    function _execute() internal override {
        MetaMorphoV1_1Market morphoMarketImpl =
            new MetaMorphoV1_1Market(resolver.resolve("WETH_ARM"), Mainnet.MORPHO_WETH_VAULT);
        _recordDeployment("MORPHO_MARKET_WETH_ARM_IMPL", address(morphoMarketImpl));
    }

    function _fork() internal override {
        Proxy morphoMarketProxy = Proxy(payable(resolver.resolve("MORPHO_MARKET_WETH_ARM")));
        address morphoMarketImpl = resolver.resolve("MORPHO_MARKET_WETH_ARM_IMPL");

        // Idempotent: the deployment runner can replay pending multisig actions on forks.
        if (morphoMarketProxy.implementation() == morphoMarketImpl) return;

        require(morphoMarketProxy.owner() == Mainnet.MULTISIG_5_OF_8, "Unexpected MorphoMarket owner");
        vm.prank(Mainnet.MULTISIG_5_OF_8);
        morphoMarketProxy.upgradeTo(morphoMarketImpl);
    }
}
