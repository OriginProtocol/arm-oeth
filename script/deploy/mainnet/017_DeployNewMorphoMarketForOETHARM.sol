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

contract DeployNewMorphoMarketForOETHARMScript is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "017_DeployNewMorphoMarketForOETHARM";
    bool public constant override proposalExecuted = false;

    Proxy morphoMarketProxy;
    MorphoMarket morphoMarket;
    address oldMorphoMarketStrategy;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        oldMorphoMarketStrategy = deployedContracts["MORPHO_MARKET_ORIGIN"];
        console.log("Old Morpho Market Strategy:", oldMorphoMarketStrategy);

        // 1. Deploy MorphoMarket proxy
        morphoMarketProxy = new Proxy();
        _recordDeploy("MORPHO_MARKET_ORIGIN", address(morphoMarketProxy));

        // 2. Deploy MorphoMarket
        morphoMarket = new MorphoMarket(Mainnet.OETH_ARM, Mainnet.MORPHO_MARKET_OETH_VAULT);
        _recordDeploy("MORPHO_MARKET_ORIGIN_IMPL", address(morphoMarket));

        // 3. Initialize MorphoMarket proxy with the implementation, Timelock as owner
        bytes memory data = abi.encodeWithSelector(
            Abstract4626MarketWrapper.initialize.selector, Mainnet.STRATEGIST, Mainnet.MERKLE_DISTRIBUTOR
        );
        morphoMarketProxy.initialize(address(morphoMarket), Mainnet.TIMELOCK, data);

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Update OETH ARM ActiveMarket to OETH Morpho Market");

        // 6. Add Morpho Market as an active market
        address[] memory markets = new address[](1);
        markets[0] = deployedContracts["MORPHO_MARKET_ORIGIN"];
        govProposal.action(deployedContracts["OETH_ARM"], "addMarkets(address[])", abi.encode(markets));

        // 7. Set Morpho Market as the active market
        govProposal.action(
            deployedContracts["OETH_ARM"],
            "setActiveMarket(address)",
            abi.encode(deployedContracts["MORPHO_MARKET_ORIGIN"])
        );

        govProposal.action(
            deployedContracts["OETH_ARM"], "removeMarket(address)", abi.encode(oldMorphoMarketStrategy)
        );

        govProposal.simulate();
    }
}
