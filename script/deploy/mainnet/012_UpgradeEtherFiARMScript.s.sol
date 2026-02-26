// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {EtherFiARM} from "contracts/EtherFiARM.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract $012_UpgradeEtherFiARMScript is AbstractDeployScript("012_UpgradeEtherFiARMScript") {
    EtherFiARM etherFiARMImpl;

    function _execute() internal override {
        // 1. Deploy new EtherFiARM implementation
        uint256 claimDelay = 10 minutes;
        etherFiARMImpl = new EtherFiARM(
            Mainnet.EETH,
            Mainnet.WETH,
            Mainnet.ETHERFI_WITHDRAWAL,
            claimDelay,
            1e7, // minSharesToRedeem
            1e18, // allocateThreshold
            Mainnet.ETHERFI_WITHDRAWAL_NFT
        );
        _recordDeployment("ETHERFI_ARM_IMPL", address(etherFiARMImpl));
    }

    function _fork() internal override {
        Proxy proxy = Proxy(payable(resolver.resolve("ETHER_FI_ARM")));
        address impl = resolver.resolve("ETHERFI_ARM_IMPL");

        // Skip if already upgraded on-chain
        if (proxy.implementation() == impl) return;

        vm.startPrank(proxy.owner());
        proxy.upgradeTo(impl);
        vm.stopPrank();
    }
}
