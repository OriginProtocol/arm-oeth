// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry imports
import {console} from "forge-std/console.sol";

// Contract imports
import {Proxy} from "contracts/Proxy.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MorphoMarket} from "contracts/markets/MorphoMarket.sol";

// Deployment imports
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract UpgradeLidoARMSetBufferScript is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "009_UpgradeLidoARMSetBufferScript";
    bool public constant override proposalExecuted = false;

    Proxy morphoMarketProxy;
    LidoARM lidoARMImpl;
    MorphoMarket morphoMarket;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy new Lido implementation
        uint256 claimDelay = tenderlyTestnet ? 1 minutes : 10 minutes;
        lidoARMImpl = new LidoARM(Mainnet.STETH, Mainnet.WETH, Mainnet.LIDO_WITHDRAWAL, claimDelay, 1e7, 1e18);
        _recordDeploy("LIDO_ARM_IMPL", address(lidoARMImpl));

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Update Lido ARM to allow operator to setBuffer()");

        govProposal.action(
            deployedContracts["LIDO_ARM"], "upgradeTo(address)", abi.encode(deployedContracts["LIDO_ARM_IMPL"])
        );

        govProposal.action(
            deployedContracts["LIDO_ARM"], "setCapManager(address)", abi.encode(address(0))
        );

        govProposal.simulate();
    }
}
