// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry imports
import {console} from "forge-std/console.sol";

// Contract imports
import {Proxy} from "contracts/Proxy.sol";
import {EtherFiARM} from "contracts/EtherFiARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MorphoMarket} from "contracts/markets/MorphoMarket.sol";

// Deployment imports
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract UpgradeEtherFiARMScript is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "012_UpgradeEtherFiARMScript";
    bool public constant override proposalExecuted = true;

    Proxy morphoMarketProxy;
    EtherFiARM etherFiARMImpl;
    MorphoMarket morphoMarket;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy new EtherFiARM implementation
        uint256 claimDelay = tenderlyTestnet ? 1 minutes : 10 minutes;
        etherFiARMImpl = new EtherFiARM(
            Mainnet.EETH,
            Mainnet.WETH,
            Mainnet.ETHERFI_WITHDRAWAL,
            claimDelay,
            1e7, // minSharesToRedeem
            1e18, // allocateThreshold
            Mainnet.ETHERFI_WITHDRAWAL_NFT,
            Mainnet.ETHERFI_REDEMPTION_MANAGER
        );
        _recordDeploy("ETHERFI_ARM_IMPL", address(etherFiARMImpl));

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _fork() internal override {
        vm.startPrank(Proxy(payable(deployedContracts["ETHER_FI_ARM"])).owner());
        Proxy(payable(deployedContracts["ETHER_FI_ARM"])).upgradeTo(address(etherFiARMImpl));
        vm.stopPrank();
    }
}
