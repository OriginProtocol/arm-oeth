// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract $015_UpgradeEthenaARMScript is AbstractDeployScript("015_UpgradeEthenaARMScript") {
    EthenaARM armImpl;

    function _execute() internal override {
        // 1. Deploy new ARM implementation
        uint256 claimDelay = 10 minutes;
        armImpl = new EthenaARM(
            Mainnet.USDE,
            Mainnet.SUSDE,
            claimDelay,
            1e18, // minSharesToRedeem
            100e18 // allocateThreshold
        );
        _recordDeployment("ETHENA_ARM_IMPL", address(armImpl));
    }

    function _fork() internal override {
        vm.startPrank(Proxy(payable(resolver.resolve("ETHENA_ARM"))).owner());
        Proxy(payable(resolver.resolve("ETHENA_ARM"))).upgradeTo(address(armImpl));
        vm.stopPrank();
    }
}

