// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Proxy} from "contracts/Proxy.sol";
import {EtherFiARM} from "contracts/EtherFiARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {WeETHAssetAdapter} from "contracts/adapters/WeETHAssetAdapter.sol";
import {EtherFiAssetAdapter} from "contracts/adapters/EtherFiAssetAdapter.sol";

import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $032_UpgradeEtherFiARMSwapFeeScript is AbstractDeployScript("032_UpgradeEtherFiARMSwapFeeScript") {
    using GovHelper for GovProposal;

    bool public constant override skip = false;

    // Prices are intentionally set wider than the current on-chain prices (buy ~0.9992, sell ~0.99998)
    // to discourage swaps right after the upgrade. The operator can tighten them later via setPrices().
    /// @notice Buy price for eETH and weETH. 0.998e36 = 0.998 WETH per base asset (~20 bps below par).
    uint256 internal constant BASE_ASSET_BUY_PRICE = 0.998e36;
    /// @notice Sell price for eETH and weETH. 1e36 = 1 WETH per base asset.
    uint256 internal constant BASE_ASSET_SELL_PRICE = 1e36;
    /// @notice totalAssets() valuation price for eETH and weETH. 0.99996e36 = 0.99996 WETH per base asset.
    /// Matches the crossPrice currently set on-chain.
    uint256 internal constant BASE_ASSET_CROSS_PRICE = 0.99996e36;

    function _execute() internal override {
        uint256 claimDelay = 10 minutes;
        uint256 minSharesToRedeem = 1e7;
        int256 allocateThreshold = 1e18;
        EtherFiARM etherFiARMImpl =
            new EtherFiARM(Mainnet.EETH, Mainnet.WETH, claimDelay, minSharesToRedeem, allocateThreshold);
        _recordDeployment("ETHERFI_ARM_IMPL", address(etherFiARMImpl));

        // Deploy the eETH adapter behind a proxy and initialize it through the proxy. initialize() sets
        // the adapter's eETH approval to the Ether.fi withdrawal queue; without it requestBaseAssetRedeem
        // would revert. The proxy admin/owner is the Timelock.
        EtherFiAssetAdapter etherFiAdapterImpl = new EtherFiAssetAdapter(
            resolver.resolve("ETHER_FI_ARM"),
            Mainnet.EETH,
            Mainnet.WETH,
            Mainnet.ETHERFI_WITHDRAWAL,
            Mainnet.ETHERFI_WITHDRAWAL_NFT
        );
        _recordDeployment("ETHER_FI_ARM_EETH_ADAPTER_IMPL", address(etherFiAdapterImpl));
        Proxy etherFiAdapterProxy = new Proxy();
        etherFiAdapterProxy.initialize(
            address(etherFiAdapterImpl), Mainnet.TIMELOCK, abi.encodeWithSignature("initialize()")
        );
        _recordDeployment("ETHER_FI_ARM_EETH_ADAPTER", address(etherFiAdapterProxy));

        // Deploy the weETH adapter behind a proxy and initialize it the same way.
        WeETHAssetAdapter weETHAdapterImpl = new WeETHAssetAdapter(
            resolver.resolve("ETHER_FI_ARM"),
            Mainnet.WEETH,
            Mainnet.EETH,
            Mainnet.WETH,
            Mainnet.ETHERFI_WITHDRAWAL,
            Mainnet.ETHERFI_WITHDRAWAL_NFT
        );
        _recordDeployment("ETHER_FI_ARM_WEETH_ADAPTER_IMPL", address(weETHAdapterImpl));
        Proxy weETHAdapterProxy = new Proxy();
        weETHAdapterProxy.initialize(
            address(weETHAdapterImpl), Mainnet.TIMELOCK, abi.encodeWithSignature("initialize()")
        );
        _recordDeployment("ETHER_FI_ARM_WEETH_ADAPTER", address(weETHAdapterProxy));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription(
            "Collect legacy EtherFi ARM fees, upgrade to swap-only fee accrual, register eETH and weETH base assets with zero swap limits, and unpause the ARM"
        );

        address etherFiARMProxy = resolver.resolve("ETHER_FI_ARM");
        govProposal.action(etherFiARMProxy, "collectFees()", "");
        govProposal.action(
            etherFiARMProxy,
            "upgradeToAndCall(address,bytes)",
            abi.encode(resolver.resolve("ETHERFI_ARM_IMPL"), _checkNoLegacyWithdrawQueueData())
        );
        // The upgrade migrates the EtherFi ARM to the multi-base model, leaving baseAssetConfigs empty.
        // Both eETH and weETH are registered with zero swap limits so no swaps can happen right after
        // the upgrade. The operator will enable trading later via setPrices() with non-zero
        // buy/sell amounts once the prices are confirmed.
        govProposal.action(
            etherFiARMProxy,
            "addBaseAsset(address,address,uint256,uint256,uint256,uint256,uint256,bool)",
            abi.encode(
                Mainnet.EETH,
                resolver.resolve("ETHER_FI_ARM_EETH_ADAPTER"),
                BASE_ASSET_BUY_PRICE,
                BASE_ASSET_SELL_PRICE,
                uint256(0),
                uint256(0),
                BASE_ASSET_CROSS_PRICE,
                true
            )
        );
        govProposal.action(
            etherFiARMProxy,
            "addBaseAsset(address,address,uint256,uint256,uint256,uint256,uint256,bool)",
            abi.encode(
                Mainnet.WEETH,
                resolver.resolve("ETHER_FI_ARM_WEETH_ADAPTER"),
                BASE_ASSET_BUY_PRICE,
                BASE_ASSET_SELL_PRICE,
                uint256(0),
                uint256(0),
                BASE_ASSET_CROSS_PRICE,
                false
            )
        );
        // The ARM is paused ahead of the upgrade; unpause it so deposits/redeems work again.
        // Swaps remain blocked by the zero swap limits until the operator enables them.
        govProposal.action(etherFiARMProxy, "unpause()", "");
    }

    function _fork() internal override {
        Proxy proxy = Proxy(payable(resolver.resolve("ETHER_FI_ARM")));
        address impl = resolver.resolve("ETHERFI_ARM_IMPL");

        if (proxy.implementation() == impl) return;

        vm.startPrank(proxy.owner());
        EtherFiARM(payable(address(proxy))).collectFees();
        proxy.upgradeToAndCall(impl, _checkNoLegacyWithdrawQueueData());

        // Mirror the governance proposal so the runFork() path leaves the ARM in the same multi-base
        // state: eETH and weETH both registered with zero swap limits (no swaps until the operator
        // enables them via setPrices()).
        EtherFiARM(payable(address(proxy)))
            .addBaseAsset(
                Mainnet.EETH,
                resolver.resolve("ETHER_FI_ARM_EETH_ADAPTER"),
                BASE_ASSET_BUY_PRICE,
                BASE_ASSET_SELL_PRICE,
                0,
                0,
                BASE_ASSET_CROSS_PRICE,
                true
            );
        EtherFiARM(payable(address(proxy)))
            .addBaseAsset(
                Mainnet.WEETH,
                resolver.resolve("ETHER_FI_ARM_WEETH_ADAPTER"),
                BASE_ASSET_BUY_PRICE,
                BASE_ASSET_SELL_PRICE,
                0,
                0,
                BASE_ASSET_CROSS_PRICE,
                false
            );
        EtherFiARM(payable(address(proxy))).unpause();
        vm.stopPrank();
    }

    function _checkNoLegacyWithdrawQueueData() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(EtherFiARM.checkNoLegacyWithdrawQueue.selector);
    }
}
