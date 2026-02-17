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

contract DeployNewMorphoMarketForEtherFiARM is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "017_DeployNewMorphoMarketForEtherFiARM";
    bool public constant override proposalExecuted = false;

    Proxy morphoMarketProxy;
    MorphoMarket morphoMarket;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy MorphoMarket proxy
        morphoMarketProxy = new Proxy();
        _recordDeploy("MORPHO_MARKET_ETHERFI", address(morphoMarketProxy));

        // 2. Deploy MorphoMarket
        morphoMarket = new MorphoMarket(Mainnet.ETHERFI_ARM, Mainnet.MORPHO_MARKET_OETH_VAULT);
        _recordDeploy("MORPHO_MARKET_ETHERFI_IMPL", address(morphoMarket));
        // 3. Initialize MorphoMarket proxy with the implementation, Timelock as owner
        bytes memory data = abi.encodeWithSelector(
            Abstract4626MarketWrapper.initialize.selector, Mainnet.STRATEGIST, Mainnet.MERKLE_DISTRIBUTOR
        );
        morphoMarketProxy.initialize(address(morphoMarket), Mainnet.TIMELOCK, data);

        console.log("Finished deploying", DEPLOY_NAME);
    }
}
