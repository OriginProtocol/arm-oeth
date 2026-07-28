// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MultiAssetARM} from "contracts/MultiAssetARM.sol";
import {OriginAssetAdapter} from "contracts/adapters/OriginAssetAdapter.sol";
import {WrappedOriginAssetAdapter} from "contracts/adapters/WrappedOriginAssetAdapter.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

/// @title Add Origin assets to the WETH ARM
/// @notice Deploys OETH and wOETH adapters that redeem through the OETH Vault's asynchronous
///         withdrawal queue, then registers both tokens as base assets on the existing WETH ARM.
/// @dev The adapter proxies are owned by the mainnet 2/8 multisig. The same multisig owns the WETH
///      ARM and performs the base-asset registration actions simulated by `_fork()`.
contract $043_AddOriginAssetsToWETHARMScript is AbstractDeployScript("043_AddOriginAssetsToWETHARMScript") {
    /// 0.99996e36 = base asset valued at 0.99996 WETH in totalAssets().
    uint256 internal constant CROSS_PRICE = 0.99996e36;
    /// 0.9997e36 = ARM pays 0.9997 WETH per base asset bought from traders.
    uint256 internal constant BUY_PRICE = 0.9997e36;
    /// 1e36 = ARM charges 1 WETH per base asset sold to traders.
    uint256 internal constant SELL_PRICE = 1e36;

    function _execute() internal override {
        address wethARM = resolver.resolve("WETH_ARM");

        // 1. Deploy the adapter for rebasing OETH.
        OriginAssetAdapter oethAdapterImpl =
            new OriginAssetAdapter(wethARM, Mainnet.OETH, Mainnet.WETH, Mainnet.OETH_VAULT);
        _recordDeployment("WETH_ARM_OETH_ADAPTER_IMPL", address(oethAdapterImpl));

        Proxy oethAdapterProxy = new Proxy();
        oethAdapterProxy.initialize(
            address(oethAdapterImpl), Mainnet.MULTISIG_2_OF_8, abi.encodeWithSignature("initialize()")
        );
        _recordDeployment("WETH_ARM_OETH_ADAPTER", address(oethAdapterProxy));

        // 2. Deploy the adapter that unwraps wOETH before requesting an OETH Vault withdrawal.
        WrappedOriginAssetAdapter woethAdapterImpl =
            new WrappedOriginAssetAdapter(wethARM, Mainnet.WOETH, Mainnet.OETH, Mainnet.WETH, Mainnet.OETH_VAULT);
        _recordDeployment("WETH_ARM_WOETH_ADAPTER_IMPL", address(woethAdapterImpl));

        Proxy woethAdapterProxy = new Proxy();
        woethAdapterProxy.initialize(
            address(woethAdapterImpl), Mainnet.MULTISIG_2_OF_8, abi.encodeWithSignature("initialize()")
        );
        _recordDeployment("WETH_ARM_WOETH_ADAPTER", address(woethAdapterProxy));
    }

    function _fork() internal override {
        MultiAssetARM wethARM = MultiAssetARM(payable(resolver.resolve("WETH_ARM")));

        // Idempotent: the deployment runner can replay pending multisig actions on forks.
        (,,,,,,,, address oethAdapter) = wethARM.baseAssetConfigs(Mainnet.OETH);
        if (oethAdapter == address(0)) {
            vm.prank(Mainnet.MULTISIG_2_OF_8);
            wethARM.addBaseAsset(
                Mainnet.OETH,
                resolver.resolve("WETH_ARM_OETH_ADAPTER"),
                BUY_PRICE,
                SELL_PRICE,
                0, // buyAmount: no swaps until the operator sets swap limits.
                0, // sellAmount
                CROSS_PRICE,
                true // OETH is accounted for 1:1 with WETH.
            );
        }

        (,,,,,,,, address woethAdapter) = wethARM.baseAssetConfigs(Mainnet.WOETH);
        if (woethAdapter == address(0)) {
            vm.prank(Mainnet.MULTISIG_2_OF_8);
            wethARM.addBaseAsset(
                Mainnet.WOETH,
                resolver.resolve("WETH_ARM_WOETH_ADAPTER"),
                BUY_PRICE,
                SELL_PRICE,
                0, // buyAmount: no swaps until the operator sets swap limits.
                0, // sellAmount
                CROSS_PRICE,
                false // wOETH is valued through its ERC-4626 conversion rate.
            );
        }
    }
}
