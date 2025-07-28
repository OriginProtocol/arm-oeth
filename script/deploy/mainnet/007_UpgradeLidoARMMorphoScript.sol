// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry imports
import {console} from "forge-std/console.sol";

// Contract imports
import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MorphoMarket} from "contracts/markets/MorphoMarket.sol";

// Deployment imports
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract UpgradeLidoARMMorphoScript is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "007_UpgradeLidoARMMorphoScript";
    bool public constant override proposalExecuted = false;

    LidoARM lidoARMImpl;
    MorphoMarket morphoMarket;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy new Lido implementation
        uint256 claimDelay = tenderlyTestnet ? 1 minutes : 10 minutes;
        lidoARMImpl = new LidoARM(Mainnet.STETH, Mainnet.WETH, Mainnet.LIDO_WITHDRAWAL, claimDelay);
        _recordDeploy("LIDO_ARM_IMPL", address(lidoARMImpl));

        // 2. Deploy MorphoMarket
        morphoMarket = new MorphoMarket(Mainnet.LIDO_ARM, Mainnet.MORPHO_MARKET_MEVCAPITAL);
        _recordDeploy("MORPHO_MARKET_MEVCAPITAL", address(morphoMarket));

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Update Lido ARM to Morpho Market");

        govProposal.action(deployedContracts["LIDO_ARM"], "upgradeTo(address)", abi.encode(deployedContracts["LIDO_ARM_IMPL"]));

        govProposal.simulate();
    }
}
