// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry imports
import {console} from "forge-std/console.sol";

// Contract imports
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MorphoMarket} from "contracts/markets/MorphoMarket.sol";

// Deployment imports
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract UpgradeMorphoMarketScript is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "013_UpgradeMorphoMarketScript";
    bool public constant override proposalExecuted = false;

    MorphoMarket morphoMarket;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy new MorphoMarket implementation
        morphoMarket = new MorphoMarket(Mainnet.LIDO_ARM, Mainnet.MORPHO_MARKET_MEVCAPITAL);
        _recordDeploy("MORPHO_MARKET_MEVCAPITAL_IMP", address(morphoMarket));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Update Morpho Market from LidoARM to support Merkle Distributor");

        // 1. Upgrade MorphoMarket to new implementation
        govProposal.action(
            deployedContracts["MORPHO_MARKET_MEVCAPITAL"],
            "upgradeTo(address)",
            abi.encode(deployedContracts["MORPHO_MARKET_MEVCAPITAL_IMP"])
        );

        // 2. Set the MerkleDistributor address in the MorphoMarket
        govProposal.action(
            deployedContracts["MORPHO_MARKET_MEVCAPITAL"],
            "setMerkleDistributor(address)",
            abi.encode(Mainnet.MERKLE_DISTRIBUTOR)
        );

        govProposal.simulate();
    }
}
