// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract imports
import {Proxy} from "contracts/Proxy.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract $020_UpgradeEthenaARMScript is AbstractDeployScript("020_UpgradeEthenaARMScript") {
    EthenaARM armImpl;

    function _execute() internal override {
        // 1. Deploy new ARM implementation
        armImpl = new EthenaARM(
            Mainnet.USDE,
            Mainnet.SUSDE,
            10 minutes, // claimDelay
            1e18, // minSharesToRedeem
            100e18 // allocateThreshold
        );
        _recordDeployment("ETHENA_ARM_IMPL", address(armImpl));
    }

    function _fork() internal override {
        Proxy proxy = Proxy(payable(resolver.resolve("ETHENA_ARM")));
        address impl = resolver.resolve("ETHENA_ARM_IMPL");

        // Skip if already upgraded on-chain
        if (proxy.implementation() == impl) return;

        vm.startPrank(proxy.owner());
        proxy.upgradeTo(impl);
        vm.stopPrank();
    }
}
