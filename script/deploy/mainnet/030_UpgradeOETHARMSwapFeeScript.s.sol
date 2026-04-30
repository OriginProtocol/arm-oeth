// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Proxy} from "contracts/Proxy.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $030_UpgradeOETHARMSwapFeeScript is AbstractDeployScript("030_UpgradeOETHARMSwapFeeScript") {
    using GovHelper for GovProposal;

    function _execute() internal override {
        uint256 claimDelay = 10 minutes;
        uint256 minSharesToRedeem = 1e7;
        int256 allocateThreshold = 1e18;
        OriginARM oethARMImpl = new OriginARM(
            Mainnet.OETH, Mainnet.WETH, Mainnet.OETH_VAULT, claimDelay, minSharesToRedeem, allocateThreshold
        );
        _recordDeployment("OETH_ARM_IMPL", address(oethARMImpl));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Upgrade OETH ARM to swap-only fee accrual");

        address oethARMProxy = resolver.resolve("OETH_ARM");
        govProposal.action(oethARMProxy, "upgradeTo(address)", abi.encode(resolver.resolve("OETH_ARM_IMPL")));
    }

    function _fork() internal override {
        Proxy proxy = Proxy(payable(resolver.resolve("OETH_ARM")));
        address impl = resolver.resolve("OETH_ARM_IMPL");

        if (proxy.implementation() == impl) return;

        vm.prank(proxy.owner());
        proxy.upgradeTo(impl);
    }
}
