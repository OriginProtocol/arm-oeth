// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract imports
import {Proxy} from "contracts/Proxy.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment imports
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract UpgradeEthenaARMScript is AbstractDeployScript("015_UpgradeEthenaARMScript") {
    using GovHelper for GovProposal;

    bool public override skip = false;
    bool public constant override proposalExecuted = true;

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
        vm.startPrank(Proxy(payable(resolver.implementations("ETHENA_ARM"))).owner());
        Proxy(payable(resolver.implementations("ETHENA_ARM"))).upgradeTo(address(armImpl));
        vm.stopPrank();
    }
}

