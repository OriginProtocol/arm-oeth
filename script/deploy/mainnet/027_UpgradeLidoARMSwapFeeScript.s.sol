// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {Proxy} from "contracts/Proxy.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $027_UpgradeLidoARMSwapFeeScript is AbstractDeployScript("027_UpgradeLidoARMSwapFeeScript") {
    using GovHelper for GovProposal;

    bool public constant override skip = true;

    function _execute() internal override {
        uint256 claimDelay = 10 minutes;
        uint256 minSharesToRedeem = 1e7;
        int256 allocateThreshold = 1e18;
        LidoARM lidoARMImpl = new LidoARM(
            Mainnet.STETH, Mainnet.WETH, Mainnet.LIDO_WITHDRAWAL, claimDelay, minSharesToRedeem, allocateThreshold
        );
        _recordDeployment("LIDO_ARM_IMPL", address(lidoARMImpl));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Collect legacy Lido ARM fees and upgrade to swap-only fee accrual");

        address lidoARMProxy = resolver.resolve("LIDO_ARM");
        govProposal.action(lidoARMProxy, "collectFees()", "");
        govProposal.action(lidoARMProxy, "upgradeTo(address)", abi.encode(resolver.resolve("LIDO_ARM_IMPL")));
    }

    function _fork() internal override {
        Proxy proxy = Proxy(payable(resolver.resolve("LIDO_ARM")));
        address impl = resolver.resolve("LIDO_ARM_IMPL");

        if (proxy.implementation() == impl) return;

        vm.startPrank(proxy.owner());
        // Legacy fees must be collected before the proxy switches to the new swap-only fee logic.
        LidoARM(payable(address(proxy))).collectFees();
        proxy.upgradeTo(impl);
        vm.stopPrank();
    }
}
