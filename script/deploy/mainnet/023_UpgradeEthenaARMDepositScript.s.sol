// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {Proxy} from "contracts/Proxy.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract $023_UpgradeEthenaARMDepositScript is AbstractDeployScript("023_UpgradeEthenaARMDepositScript") {
    EthenaARM armImpl;

    function _execute() internal override {
        // 1. Deploy new EthenaARM implementation
        uint256 claimDelay = 10 minutes;
        uint256 minSharesToRedeem = 1e18;
        int256 allocateThreshold = 100e18;
        armImpl = new EthenaARM(Mainnet.USDE, Mainnet.SUSDE, claimDelay, minSharesToRedeem, allocateThreshold);
        _recordDeployment("ETHENA_ARM_IMPL", address(armImpl));
    }

    function _fork() internal override {
        vm.startPrank(Proxy(payable(resolver.resolve("ETHENA_ARM"))).owner());
        Proxy(payable(resolver.resolve("ETHENA_ARM"))).upgradeTo(address(armImpl));
        vm.stopPrank();
    }
}
