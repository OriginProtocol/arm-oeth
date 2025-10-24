// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry imports
import {console} from "forge-std/console.sol";

// Contract imports
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {OriginARM} from "contracts/OriginARM.sol";

// Deployment imports
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract UpgradeOETHARMScript is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "012_UpgradeOETHARMScript";
    bool public constant override proposalExecuted = false;

    Proxy morphoMarketProxy;
    OriginARM originARMImpl;
    OriginARM oethARM;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy new Origin implementation
        uint256 claimDelay = tenderlyTestnet ? 1 minutes : 10 minutes;
        originARMImpl = new OriginARM(Mainnet.OETH, Mainnet.WETH, Mainnet.OETH_VAULT, claimDelay, 1e7, 1e18);
        _recordDeploy("OETH_ARM_IMPL", address(originARMImpl));

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Update OETH ARM to use Origin ARM contract");

        // 1. Timelock needs to approve the OETH ARM to pull WETH for initialization.
        govProposal.action(Mainnet.WETH, "approve(address,uint256)", abi.encode(deployedContracts["OETH_ARM"], 1e12));

        // 2. Upgrade the OETH ARM implementation, and initialize.
        bytes memory initializeData = abi.encodeWithSelector(
            OriginARM.initialize.selector,
            "Origin ARM",
            "ARM-WETH-OETH",
            Mainnet.ARM_RELAYER,
            2000, // 20% performance fee
            Mainnet.ARM_BUYBACK,
            address(0)
        );

        govProposal.action(
            deployedContracts["OETH_ARM"],
            "upgradeToAndCall(address,bytes)",
            abi.encode(deployedContracts["OETH_ARM_IMPL"], initializeData)
        );

        govProposal.simulate();
    }
}
