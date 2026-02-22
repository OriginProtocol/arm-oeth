// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry imports
import {console} from "forge-std/console.sol";

// Contract imports
import {Proxy} from "contracts/Proxy.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment imports
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract UpgradeEthenaARMScript is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "020_UpgradeEthenaARMScript";
    bool public constant override proposalExecuted = false;

    EthenaARM armImpl;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy new ARM implementation
        uint256 claimDelay = tenderlyTestnet ? 1 minutes : 10 minutes;
        armImpl = new EthenaARM(
            Mainnet.USDE,
            Mainnet.SUSDE,
            claimDelay,
            1e18, // minSharesToRedeem
            100e18 // allocateThreshold
        );
        _recordDeploy("ETHENA_ARM_IMPL", address(armImpl));

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _fork() internal override {
        vm.startPrank(Proxy(payable(deployedContracts["ETHENA_ARM"])).owner());
        Proxy(payable(deployedContracts["ETHENA_ARM"])).upgradeTo(address(armImpl));
        vm.stopPrank();
    }
}
