// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MultiAssetARM} from "contracts/MultiAssetARM.sol";
import {PaxosAssetAdapter} from "contracts/adapters/PaxosAssetAdapter.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {ARMDeploymentHelper} from "script/deploy/helpers/ARMDeploymentHelper.sol";

/// @title Upgrade the USDC ARM and Paxos adapters to support base-asset minting
/// @notice Deploys a mint-capable MultiAssetARM implementation and new PYUSD and USDG Paxos adapter
///         implementations. The existing proxies are upgraded by their owner, the Ethereum 5/8
///         multisig, and each adapter's mint recipient is initialized from its existing Paxos
///         redemption recipient.
/// @dev Deploys ARMAdapterLib first, then links the MultiAssetARM creation bytecode to that exact
///      address at runtime. This avoids leaving an unlinked library placeholder in the dynamically
///      loaded deployment script. This is a logic-only proxy upgrade: proxy storage is preserved and
///      no proxy reinitializer is required. Fork actions are idempotent so they can be replayed safely.
contract $043_UpgradeUSDCARMMintScript is AbstractDeployScript("043_UpgradeUSDCARMMintScript") {
    function _execute() internal override {
        address usdcARM = resolver.resolve("USDC_ARM");

        address adapterLib = ARMDeploymentHelper.deployARMAdapterLib();
        _recordDeployment("ARM_ADAPTER_LIB", adapterLib);

        // Use the same immutable constructor parameters as 039_DeployUSDCARMScript.
        MultiAssetARM armImpl = ARMDeploymentHelper.deployMultiAssetARM(
            vm,
            projectRoot,
            adapterLib,
            ARMDeploymentHelper.MultiAssetARMConfig({
                liquidityAsset: Mainnet.USDC,
                claimDelay: 10 minutes,
                minSharesToRedeem: 1e6, // 1e6 = 1 USDC of minimum market shares to redeem
                allocateThreshold: 100e6 // 100e6 = 100 USDC
            })
        );
        _recordDeployment("USDC_ARM_IMPL", address(armImpl));

        PaxosAssetAdapter pyusdAdapterImpl = new PaxosAssetAdapter(usdcARM, Mainnet.PYUSD, Mainnet.USDC);
        _recordDeployment("USDC_ARM_PYUSD_ADAPTER_IMPL", address(pyusdAdapterImpl));

        PaxosAssetAdapter usdgAdapterImpl = new PaxosAssetAdapter(usdcARM, Mainnet.USDG, Mainnet.USDC);
        _recordDeployment("USDC_ARM_USDG_ADAPTER_IMPL", address(usdgAdapterImpl));
    }

    function _fork() internal override {
        // Upgrade the adapters first so mint requests are supported as soon as the ARM is upgraded.
        _upgradeProxy("USDC_ARM_PYUSD_ADAPTER", "USDC_ARM_PYUSD_ADAPTER_IMPL");
        _upgradeProxy("USDC_ARM_USDG_ADAPTER", "USDC_ARM_USDG_ADAPTER_IMPL");

        // Existing proxies predate paxosMintRecipient. Use their already configured Paxos recipient
        // as the initial mint recipient, matching initialize() for newly deployed adapters.
        _initializeMintRecipient("USDC_ARM_PYUSD_ADAPTER");
        _initializeMintRecipient("USDC_ARM_USDG_ADAPTER");

        _upgradeProxy("USDC_ARM", "USDC_ARM_IMPL");
    }

    function _upgradeProxy(string memory proxyName, string memory implementationName) internal {
        Proxy proxy = Proxy(payable(resolver.resolve(proxyName)));
        address implementation = resolver.resolve(implementationName);

        if (proxy.implementation() == implementation) return;

        require(proxy.owner() == Mainnet.MULTISIG_5_OF_8, "Unexpected proxy owner");
        vm.prank(Mainnet.MULTISIG_5_OF_8);
        proxy.upgradeTo(implementation);
    }

    function _initializeMintRecipient(string memory adapterName) internal {
        PaxosAssetAdapter adapter = PaxosAssetAdapter(resolver.resolve(adapterName));
        if (adapter.paxosMintRecipient() != address(0)) return;

        address recipient = adapter.paxosRecipient();
        require(recipient != address(0), "Paxos recipient not configured");

        Proxy proxy = Proxy(payable(address(adapter)));
        require(proxy.owner() == Mainnet.MULTISIG_5_OF_8, "Unexpected adapter owner");
        vm.prank(Mainnet.MULTISIG_5_OF_8);
        adapter.setPaxosMintRecipient(recipient);
    }
}
