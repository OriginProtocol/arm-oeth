// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Proxy} from "contracts/Proxy.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {StETHAssetAdapter} from "contracts/adapters/StETHAssetAdapter.sol";
import {WstETHAssetAdapter} from "contracts/adapters/WstETHAssetAdapter.sol";

import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $033_UpgradeLidoARMSwapFeeScript is AbstractDeployScript("033_UpgradeLidoARMSwapFeeScript") {
    using GovHelper for GovProposal;

    bool public constant override skip = true;

    // Prices are intentionally set wider than the current on-chain prices (buy ~0.9998, sell 1.0)
    // to discourage swaps right after the upgrade. The operator can tighten them later via setPrices().
    /// @notice Buy price for stETH and wstETH. 0.998e36 = 0.998 WETH per base asset (~20 bps below par).
    uint256 internal constant BASE_ASSET_BUY_PRICE = 0.998e36;
    /// @notice Sell price for stETH and wstETH. 1e36 = 1 WETH per base asset.
    uint256 internal constant BASE_ASSET_SELL_PRICE = 1e36;
    /// @notice totalAssets() valuation price for stETH and wstETH. 0.99996e36 = 0.99996 WETH per base asset.
    /// Matches the crossPrice currently set on-chain.
    uint256 internal constant BASE_ASSET_CROSS_PRICE = 0.99996e36;

    function _execute() internal override {
        uint256 claimDelay = 10 minutes;
        uint256 minSharesToRedeem = 1e7;
        int256 allocateThreshold = 1e18;
        LidoARM lidoARMImpl = new LidoARM(Mainnet.WETH, claimDelay, minSharesToRedeem, allocateThreshold);
        _recordDeployment("LIDO_ARM_IMPL", address(lidoARMImpl));

        // Deploy the stETH adapter behind a proxy and initialize it through the proxy. initialize() sets
        // the adapter's stETH approval to the Lido withdrawal queue; without it requestBaseAssetRedeem
        // would revert. The proxy admin/owner is the Timelock.
        StETHAssetAdapter stethAdapterImpl =
            new StETHAssetAdapter(resolver.resolve("LIDO_ARM"), Mainnet.WETH, Mainnet.STETH, Mainnet.LIDO_WITHDRAWAL);
        _recordDeployment("LIDO_ARM_STETH_ADAPTER_IMPL", address(stethAdapterImpl));
        Proxy stethAdapterProxy = new Proxy();
        stethAdapterProxy.initialize(
            address(stethAdapterImpl), Mainnet.TIMELOCK, abi.encodeWithSignature("initialize()")
        );
        _recordDeployment("LIDO_ARM_STETH_ADAPTER", address(stethAdapterProxy));

        // Deploy the wstETH adapter behind a proxy and initialize it the same way.
        WstETHAssetAdapter wstethAdapterImpl = new WstETHAssetAdapter(
            resolver.resolve("LIDO_ARM"), Mainnet.WETH, Mainnet.STETH, Mainnet.WSTETH, Mainnet.LIDO_WITHDRAWAL
        );
        _recordDeployment("LIDO_ARM_WSTETH_ADAPTER_IMPL", address(wstethAdapterImpl));
        Proxy wstethAdapterProxy = new Proxy();
        wstethAdapterProxy.initialize(
            address(wstethAdapterImpl), Mainnet.TIMELOCK, abi.encodeWithSignature("initialize()")
        );
        _recordDeployment("LIDO_ARM_WSTETH_ADAPTER", address(wstethAdapterProxy));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Collect legacy Lido ARM fees and upgrade to swap-only fee accrual");

        address lidoARMProxy = resolver.resolve("LIDO_ARM");
        govProposal.action(lidoARMProxy, "collectFees()", "");
        govProposal.action(
            lidoARMProxy,
            "upgradeToAndCall(address,bytes)",
            abi.encode(resolver.resolve("LIDO_ARM_IMPL"), _checkNoLegacyWithdrawQueueData())
        );
        // The upgrade migrates the Lido ARM to the multi-base model, leaving baseAssetConfigs empty.
        // Both stETH and wstETH are registered with zero swap limits so no swaps can happen right after
        // the upgrade. The operator will enable trading later via setPrices() with non-zero
        // buy/sell amounts once the prices are confirmed.
        govProposal.action(
            lidoARMProxy,
            "addBaseAsset(address,address,uint256,uint256,uint256,uint256,uint256,bool)",
            abi.encode(
                Mainnet.STETH,
                resolver.resolve("LIDO_ARM_STETH_ADAPTER"),
                BASE_ASSET_BUY_PRICE,
                BASE_ASSET_SELL_PRICE,
                uint256(0),
                uint256(0),
                BASE_ASSET_CROSS_PRICE,
                true
            )
        );
        govProposal.action(
            lidoARMProxy,
            "addBaseAsset(address,address,uint256,uint256,uint256,uint256,uint256,bool)",
            abi.encode(
                Mainnet.WSTETH,
                resolver.resolve("LIDO_ARM_WSTETH_ADAPTER"),
                BASE_ASSET_BUY_PRICE,
                BASE_ASSET_SELL_PRICE,
                uint256(0),
                uint256(0),
                BASE_ASSET_CROSS_PRICE,
                false
            )
        );
    }

    function _fork() internal override {
        Proxy proxy = Proxy(payable(resolver.resolve("LIDO_ARM")));
        address impl = resolver.resolve("LIDO_ARM_IMPL");

        if (proxy.implementation() == impl) return;

        vm.startPrank(proxy.owner());
        LidoARM(payable(address(proxy))).collectFees();
        proxy.upgradeToAndCall(impl, _checkNoLegacyWithdrawQueueData());

        // Mirror the governance proposal so the runFork() path leaves the ARM in the same multi-base
        // state: stETH and wstETH both registered with zero swap limits (no swaps until the operator
        // enables them via setPrices()).
        LidoARM(payable(address(proxy)))
            .addBaseAsset(
                Mainnet.STETH,
                resolver.resolve("LIDO_ARM_STETH_ADAPTER"),
                BASE_ASSET_BUY_PRICE,
                BASE_ASSET_SELL_PRICE,
                0,
                0,
                BASE_ASSET_CROSS_PRICE,
                true
            );
        LidoARM(payable(address(proxy)))
            .addBaseAsset(
                Mainnet.WSTETH,
                resolver.resolve("LIDO_ARM_WSTETH_ADAPTER"),
                BASE_ASSET_BUY_PRICE,
                BASE_ASSET_SELL_PRICE,
                0,
                0,
                BASE_ASSET_CROSS_PRICE,
                false
            );
        vm.stopPrank();
    }

    function _checkNoLegacyWithdrawQueueData() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(LidoARM.checkNoLegacyWithdrawQueue.selector);
    }
}
