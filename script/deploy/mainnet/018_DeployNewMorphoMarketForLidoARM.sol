// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry imports
import {console} from "forge-std/console.sol";

// Contract imports
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MorphoMarket} from "contracts/markets/MorphoMarket.sol";
import {Abstract4626MarketWrapper} from "contracts/markets/Abstract4626MarketWrapper.sol";

// Deployment imports
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract DeployNewMorphoMarketForLidoARM is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "018_DeployNewMorphoMarketForLidoARM";
    bool public constant override proposalExecuted = false;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy MorphoMarket proxy
        Proxy morphoMarketProxy = new Proxy();
        _recordDeploy("MORPHO_MARKET_LIDO", address(morphoMarketProxy));

        // 2. Deploy MorphoMarket
        MorphoMarket morphoMarket = new MorphoMarket(Mainnet.LIDO_ARM, Mainnet.MORPHO_MARKET_OETH_VAULT);
        _recordDeploy("MORPHO_MARKET_LIDO_IMPL", address(morphoMarket));

        // 3. Initialize MorphoMarket proxy with the implementation, Timelock as owner
        bytes memory data = abi.encodeWithSelector(
            Abstract4626MarketWrapper.initialize.selector, Mainnet.STRATEGIST, Mainnet.MERKLE_DISTRIBUTOR
        );
        morphoMarketProxy.initialize(address(morphoMarket), Mainnet.TIMELOCK, data);

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _buildGovernanceProposal() internal override {
        // 1. Set governance proposal description
        govProposal.setDescription("Change Lido ARM MorphoMarket");

        // 2. Add the new MorphoMarket to the Lido ARM
        address[] memory marketsToAdd = new address[](1);
        marketsToAdd[0] = deployedContracts["MORPHO_MARKET_LIDO"];
        govProposal.action(deployedContracts["LIDO_ARM"], "addMarkets(address[])", abi.encode(marketsToAdd));

        // 3. Set the new MorphoMarket as the active market for the Lido ARM
        govProposal.action(
            deployedContracts["LIDO_ARM"],
            "setActiveMarket(address)",
            abi.encode(deployedContracts["MORPHO_MARKET_LIDO"])
        );

        // 4. Remove the old MorphoMarket from the Lido ARM
        govProposal.action(
            deployedContracts["LIDO_ARM"],
            "removeMarket(address)",
            abi.encode(deployedContracts["MORPHO_MARKET_MEVCAPITAL"])
        );

        govProposal.simulate();
    }
}
