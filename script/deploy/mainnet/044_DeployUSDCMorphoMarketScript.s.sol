// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MultiAssetARM} from "contracts/MultiAssetARM.sol";
import {MorphoVaultV2Market} from "contracts/markets/MorphoVaultV2Market.sol";
import {Abstract4626MarketWrapper} from "contracts/markets/Abstract4626MarketWrapper.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

/// @title Deploy the USDC ARM Morpho market
/// @notice Deploys a Morpho Vault V2 wrapper for the USDC ARM and registers it as a supported
///         market. The mainnet 5/8 multisig owns the wrapper, while the 2/8 multisig harvests its
///         rewards. The market is not activated automatically.
/// @dev The 5/8 registration action is simulated in _fork(); on mainnet it is executed separately
///      by the multisig after the proxy and implementation have been deployed. No governance
///      proposal is required because the 5/8 multisig directly owns the USDC ARM.
///
///      Registration and activation are deliberately separate. Before activation, operators must
///      verify that the Vault V2 gates permit the wrapper and ARM, and that every cap used by the
///      liquidity adapter has enough headroom for the ARM's full one-transaction allocation. Vault
///      V2 automatically forwards deposits to its liquidity adapter, so an otherwise valid ARM
///      allocation can revert when an absolute or relative cap is reached.
///
///      Adapter safety is an ongoing operational assumption. The target currently uses a direct,
///      loss-aware MorphoMarketV1AdapterV2, but its curator can add adapters after deployment. While
///      this ARM market is active, operators must monitor adapter changes and deactivate it before
///      any MorphoVaultV1Adapter over MetaMorpho V1.1 becomes effective, because its lostAssets
///      accounting can keep bad debt in the reported Vault V2 share price.
///
///      Operators must also verify downstream liquidity. MorphoVaultV2Market reports its full
///      economic position from maxWithdraw/maxRedeem because Vault V2 returns zero, but those
///      wrapper values do not guarantee that an immediate withdrawal will succeed.
contract $044_DeployUSDCMorphoMarketScript is AbstractDeployScript("044_DeployUSDCMorphoMarketScript") {
    function _execute() internal override {
        address usdcARM = resolver.resolve("USDC_ARM");

        // 1. Deploy the Morpho Vault V2 market proxy.
        Proxy morphoMarketProxy = new Proxy();
        _recordDeployment("MORPHO_MARKET_USDC_ARM", address(morphoMarketProxy));

        // 2. Deploy the implementation for the USDC ARM and Wintermute USDC Prime vault.
        MorphoVaultV2Market morphoMarketImpl =
            new MorphoVaultV2Market(usdcARM, Mainnet.MORPHO_WINTERMUTE_USDC_PRIME_VAULT);
        _recordDeployment("MORPHO_MARKET_USDC_ARM_IMPL", address(morphoMarketImpl));

        // 3. Initialize the wrapper and hand ownership to the USDC ARM's 5/8 multisig.
        // The deployment does not activate the market or deposit USDC into Vault V2.
        bytes memory data = abi.encodeWithSelector(
            Abstract4626MarketWrapper.initialize.selector, Mainnet.MULTISIG_2_OF_8, Mainnet.MERKLE_DISTRIBUTOR
        );
        morphoMarketProxy.initialize(address(morphoMarketImpl), Mainnet.MULTISIG_5_OF_8, data);
    }

    function _fork() internal override {
        MultiAssetARM usdcARM = MultiAssetARM(payable(resolver.resolve("USDC_ARM")));
        address morphoMarket = resolver.resolve("MORPHO_MARKET_USDC_ARM");

        // Idempotent: the deployment runner can replay the pending multisig action on forks.
        if (usdcARM.supportedMarkets(morphoMarket)) return;

        address[] memory markets = new address[](1);
        markets[0] = morphoMarket;

        vm.prank(Mainnet.MULTISIG_5_OF_8);
        usdcARM.addMarkets(markets);
    }
}
