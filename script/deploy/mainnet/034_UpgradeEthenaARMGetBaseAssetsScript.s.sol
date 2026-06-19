// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

/// @title Upgrade Ethena ARM to expose getBaseAssets()
/// @notice Upgrades the multisig-owned Ethena ARM to a fresh EthenaARM implementation that exposes
///         the new `getBaseAssets()` getter added to AbstractARM. The 031 implementation predates the
///         getter, so this is a logic-only upgrade: storage layout is unchanged, and no adapter
///         redeployment or base-asset registration is needed (sUSDe stays registered from 031).
contract $034_UpgradeEthenaARMGetBaseAssetsScript is AbstractDeployScript("034_UpgradeEthenaARMGetBaseAssetsScript") {
    function _execute() internal override {
        // Same constructor args as the 031 deployment; only the logic (the getBaseAssets getter) changes.
        uint256 claimDelay = 10 minutes;
        EthenaARM armImpl = new EthenaARM(
            Mainnet.USDE,
            claimDelay,
            1e18, // minSharesToRedeem
            100e18 // allocateThreshold
        );

        _recordDeployment("ETHENA_ARM_IMPL", address(armImpl));
    }

    function _fork() internal override {
        Proxy proxy = Proxy(payable(resolver.resolve("ETHENA_ARM")));
        address impl = resolver.resolve("ETHENA_ARM_IMPL");

        // Idempotent: skip if the proxy already runs this implementation.
        if (proxy.implementation() == impl) return;

        // Ethena ARM is multisig-owned, so the upgrade is performed directly by the owner rather than
        // through a governance proposal. getBaseAssets() is a pure view addition, so no
        // re-initialization call is required.
        vm.prank(proxy.owner());
        proxy.upgradeTo(impl);
    }
}
