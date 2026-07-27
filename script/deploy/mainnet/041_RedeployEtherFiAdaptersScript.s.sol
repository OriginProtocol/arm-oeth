// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {EtherFiAssetAdapter} from "contracts/adapters/EtherFiAssetAdapter.sol";
import {WeETHAssetAdapter} from "contracts/adapters/WeETHAssetAdapter.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

/// @title Redeploy the WETH ARM Ether.fi adapters
/// @notice Deploys new implementations for the eETH and weETH adapters, then upgrades their existing
///         proxies. The proxies are owned directly by the mainnet 2/8 multisig, so the upgrades do not
///         require a governance proposal.
/// @dev Reusing the existing proxies preserves their addresses and withdrawal-request storage.
contract $041_RedeployEtherFiAdaptersScript is AbstractDeployScript("041_RedeployEtherFiAdaptersScript") {
    function _execute() internal override {
        address arm = resolver.resolve("WETH_ARM");

        EtherFiAssetAdapter eethAdapterImpl = new EtherFiAssetAdapter(
            arm, Mainnet.EETH, Mainnet.WETH, Mainnet.ETHERFI_WITHDRAWAL, Mainnet.ETHERFI_WITHDRAWAL_NFT
        );
        _recordDeployment("WETH_ARM_EETH_ADAPTER_IMPL", address(eethAdapterImpl));

        WeETHAssetAdapter weethAdapterImpl = new WeETHAssetAdapter(
            arm, Mainnet.WEETH, Mainnet.EETH, Mainnet.WETH, Mainnet.ETHERFI_WITHDRAWAL, Mainnet.ETHERFI_WITHDRAWAL_NFT
        );
        _recordDeployment("WETH_ARM_WEETH_ADAPTER_IMPL", address(weethAdapterImpl));
    }

    function _fork() internal override {
        _upgradeAdapter("WETH_ARM_EETH_ADAPTER", "WETH_ARM_EETH_ADAPTER_IMPL");
        _upgradeAdapter("WETH_ARM_WEETH_ADAPTER", "WETH_ARM_WEETH_ADAPTER_IMPL");
    }

    function _upgradeAdapter(string memory proxyName, string memory implementationName) internal {
        Proxy adapterProxy = Proxy(payable(resolver.resolve(proxyName)));
        address adapterImpl = resolver.resolve(implementationName);

        // Idempotent: the deployment runner can replay pending multisig actions on forks.
        if (adapterProxy.implementation() == adapterImpl) return;

        require(adapterProxy.owner() == Mainnet.MULTISIG_2_OF_8, "Unexpected adapter owner");
        vm.prank(Mainnet.MULTISIG_2_OF_8);
        adapterProxy.upgradeTo(adapterImpl);
    }
}
