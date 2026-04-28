// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {Proxy} from "contracts/Proxy.sol";
import {EtherFiARM} from "contracts/EtherFiARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract $022_UpgradeEtherFiARMDepositScript is AbstractDeployScript("022_UpgradeEtherFiARMDepositScript") {
    EtherFiARM etherFiARMImpl;

    function _execute() internal override {
        // 1. Deploy new EtherFiARM implementation
        uint256 claimDelay = 10 minutes;
        uint256 minSharesToRedeem = 1e7;
        int256 allocateThreshold = 1e18;
        etherFiARMImpl = new EtherFiARM(
            Mainnet.EETH,
            Mainnet.WETH,
            Mainnet.ETHERFI_WITHDRAWAL,
            claimDelay,
            minSharesToRedeem,
            allocateThreshold,
            Mainnet.ETHERFI_WITHDRAWAL_NFT
        );
        _recordDeployment("ETHERFI_ARM_IMPL", address(etherFiARMImpl));
    }

    function _fork() internal override {
        vm.startPrank(Proxy(payable(resolver.resolve("ETHER_FI_ARM"))).owner());
        Proxy(payable(resolver.resolve("ETHER_FI_ARM"))).upgradeTo(address(etherFiARMImpl));
        vm.stopPrank();
    }
}
