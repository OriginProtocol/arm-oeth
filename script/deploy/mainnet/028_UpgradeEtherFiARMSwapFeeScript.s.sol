// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {Proxy} from "contracts/Proxy.sol";
import {EtherFiARM} from "contracts/EtherFiARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $028_UpgradeEtherFiARMSwapFeeScript is AbstractDeployScript("028_UpgradeEtherFiARMSwapFeeScript") {
    using GovHelper for GovProposal;

    bool public constant override skip = true;

    function _execute() internal override {
        uint256 claimDelay = 10 minutes;
        uint256 minSharesToRedeem = 1e7;
        int256 allocateThreshold = 1e18;
        EtherFiARM etherFiARMImpl = new EtherFiARM(
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

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Collect legacy EtherFi ARM fees and upgrade to swap-only fee accrual");

        address etherFiARMProxy = resolver.resolve("ETHER_FI_ARM");
        govProposal.action(etherFiARMProxy, "collectFees()", "");
        govProposal.action(
            etherFiARMProxy, "upgradeTo(address)", abi.encode(resolver.resolve("ETHERFI_ARM_IMPL"))
        );
    }

    function _fork() internal override {
        Proxy proxy = Proxy(payable(resolver.resolve("ETHER_FI_ARM")));
        address impl = resolver.resolve("ETHERFI_ARM_IMPL");

        if (proxy.implementation() == impl) return;

        vm.startPrank(proxy.owner());
        // Legacy fees must be collected before the proxy switches to the new swap-only fee logic.
        EtherFiARM(payable(address(proxy))).collectFees();
        proxy.upgradeTo(impl);
        vm.stopPrank();
    }
}
