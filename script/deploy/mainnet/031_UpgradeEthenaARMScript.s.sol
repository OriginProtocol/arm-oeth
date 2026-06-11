// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {EthenaAssetAdapter} from "contracts/adapters/EthenaAssetAdapter.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract $031_UpgradeEthenaARMScript is AbstractDeployScript("031_UpgradeEthenaARMScript") {
    /// @dev Number of rotating unstaker helper slots. Matches both the legacy EthenaARM layout
    /// and `EthenaAssetAdapter.MAX_UNSTAKERS`.
    uint256 internal constant MAX_UNSTAKERS = 42;

    /// @notice Buy price for sUSDe. 0.998e36 = 0.998 USDe per sUSDe.
    uint256 internal constant BASE_ASSET_BUY_PRICE = 0.998e36;
    /// @notice Sell price for sUSDe. 1e36 = 1 USDe per sUSDe.
    uint256 internal constant BASE_ASSET_SELL_PRICE = 1e36;
    /// @notice totalAssets() valuation price for sUSDe. 0.99996e36 = 0.99996 USDe per sUSDe.
    uint256 internal constant BASE_ASSET_CROSS_PRICE = 0.99996e36;

    function _execute() internal override {
        // 1. Deploy new ARM implementation
        uint256 claimDelay = 10 minutes;
        EthenaARM armImpl = new EthenaARM(
            Mainnet.USDE,
            claimDelay,
            1e18, // minSharesToRedeem
            100e18 // allocateThreshold
        );

        _recordDeployment("ETHENA_ARM_IMPL", address(armImpl));

        // 2. Deploy the sUSDe adapter behind a proxy. The deployer is the temporary proxy owner so it
        // can deploy the unstaker set, then ownership is handed over to the multisig that owns the ARM.
        EthenaAssetAdapter adapterImpl =
            new EthenaAssetAdapter(resolver.resolve("ETHENA_ARM"), Mainnet.USDE, Mainnet.SUSDE);
        _recordDeployment("ETHENA_ARM_SUSDE_ADAPTER_IMPL", address(adapterImpl));

        Proxy adapterProxy = new Proxy();
        adapterProxy.initialize(address(adapterImpl), deployer, "");
        EthenaAssetAdapter(address(adapterProxy)).deployUnstakers();
        adapterProxy.setOwner(Mainnet.GOV_MULTISIG);
        _recordDeployment("ETHENA_ARM_SUSDE_ADAPTER", address(adapterProxy));
    }

    function _fork() internal override {
        Proxy proxy = Proxy(payable(resolver.resolve("ETHENA_ARM")));
        address impl = resolver.resolve("ETHENA_ARM_IMPL");

        // Skip if already upgraded on-chain
        if (proxy.implementation() == impl) return;

        // Resolve from the registry because _fork() may run without _execute().
        EthenaAssetAdapter adapter = EthenaAssetAdapter(resolver.resolve("ETHENA_ARM_SUSDE_ADAPTER"));

        vm.startPrank(proxy.owner());
        proxy.upgradeToAndCall(impl, _checkNoLegacyWithdrawQueueData());
        // Ethena ARM is multisig-owned, not governance-owned, so sUSDe is registered directly by the
        // owner here rather than via a governance proposal. sUSDe is the only base asset and stays
        // active with full swap limits.
        EthenaARM(payable(address(proxy)))
            .addBaseAsset(
                Mainnet.SUSDE,
                address(adapter),
                BASE_ASSET_BUY_PRICE,
                BASE_ASSET_SELL_PRICE,
                type(uint128).max,
                type(uint128).max,
                BASE_ASSET_CROSS_PRICE,
                false
            );
        vm.stopPrank();

        // The unstakers are normally deployed at adapter deployment time in _execute(). Keep a
        // defensive check for forks resolving an adapter whose unstaker set is not configured yet.
        if (adapter.unstakers(0) == address(0)) {
            vm.prank(adapter.owner());
            adapter.deployUnstakers();
        }

        // Unpause the ARM
        vm.prank(proxy.owner());
        EthenaARM(payable(address(proxy))).unpause();
    }

    function _checkNoLegacyWithdrawQueueData() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(EthenaARM.checkNoLegacyWithdrawQueue.selector);
    }
}
