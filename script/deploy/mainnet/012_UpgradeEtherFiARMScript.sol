// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract imports
import {Proxy} from "contracts/Proxy.sol";
import {EtherFiARM} from "contracts/EtherFiARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MorphoMarket} from "contracts/markets/MorphoMarket.sol";

// Deployment imports
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract UpgradeEtherFiARMScript is AbstractDeployScript("012_UpgradeEtherFiARMScript") {
    using GovHelper for GovProposal;

    bool public override skip = false;
    bool public constant override proposalExecuted = true;

    Proxy morphoMarketProxy;
    EtherFiARM etherFiARMImpl;
    MorphoMarket morphoMarket;

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
        vm.startPrank(Proxy(payable(resolver.implementations("ETHER_FI_ARM"))).owner());
        Proxy(payable(resolver.implementations("ETHER_FI_ARM"))).upgradeTo(address(etherFiARMImpl));
        vm.stopPrank();
    }
}
