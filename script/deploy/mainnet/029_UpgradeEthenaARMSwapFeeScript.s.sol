// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {Proxy} from "contracts/Proxy.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $029_UpgradeEthenaARMSwapFeeScript is AbstractDeployScript("029_UpgradeEthenaARMSwapFeeScript") {
    using GovHelper for GovProposal;

    bool public constant override skip = true;

    function _execute() internal override {
        uint256 claimDelay = 10 minutes;
        uint256 minSharesToRedeem = 1e18;
        int256 allocateThreshold = 100e18;
        EthenaARM armImpl = new EthenaARM(Mainnet.USDE, Mainnet.SUSDE, claimDelay, minSharesToRedeem, allocateThreshold);
        _recordDeployment("ETHENA_ARM_IMPL", address(armImpl));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Collect legacy Ethena ARM fees and upgrade to swap-only fee accrual");

        address ethenaARMProxy = resolver.resolve("ETHENA_ARM");
        govProposal.action(ethenaARMProxy, "collectFees()", "");
        govProposal.action(ethenaARMProxy, "upgradeTo(address)", abi.encode(resolver.resolve("ETHENA_ARM_IMPL")));
    }

    function _fork() internal override {
        Proxy proxy = Proxy(payable(resolver.resolve("ETHENA_ARM")));
        address impl = resolver.resolve("ETHENA_ARM_IMPL");

        if (proxy.implementation() == impl) return;

        vm.startPrank(proxy.owner());
        // Legacy fees must be collected before the proxy switches to the new swap-only fee logic.
        EthenaARM(payable(address(proxy))).collectFees();
        proxy.upgradeTo(impl);
        vm.stopPrank();
    }
}
