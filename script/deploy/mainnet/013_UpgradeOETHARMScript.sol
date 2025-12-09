// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry imports
import {console} from "forge-std/console.sol";

// Contract imports
import {Proxy} from "contracts/Proxy.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {MorphoMarket} from "contracts/markets/MorphoMarket.sol";
import {Abstract4626MarketWrapper} from "contracts/markets/Abstract4626MarketWrapper.sol";

// Deployment imports
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract UpgradeOETHARMScript is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "013_UpgradeOETHARMScript";
    bool public constant override proposalExecuted = false;

    Proxy morphoMarketProxy;
    OriginARM originARMImpl;
    OriginARM oethARM;
    MorphoMarket morphoMarket;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy new Origin implementation
        uint256 claimDelay = tenderlyTestnet ? 1 minutes : 10 minutes;
        originARMImpl = new OriginARM(Mainnet.OETH, Mainnet.WETH, Mainnet.OETH_VAULT, claimDelay, 1e7, 1e18);
        _recordDeploy("OETH_ARM_IMPL", address(originARMImpl));

        // 2. Deploy MorphoMarket proxy
        morphoMarketProxy = new Proxy();
        _recordDeploy("MORPHO_MARKET_ORIGIN", address(morphoMarketProxy));

        // 3. Deploy MorphoMarket
        morphoMarket = new MorphoMarket(Mainnet.OETH_ARM, Mainnet.MORPHO_MARKET_YEARN_OG);
        _recordDeploy("MORPHO_MARKET_ORIGIN_IMPL", address(morphoMarket));
        // 4. Initialize MorphoMarket proxy with the implementation, Timelock as owner
        bytes memory data = abi.encodeWithSelector(
            Abstract4626MarketWrapper.initialize.selector, Mainnet.STRATEGIST, Mainnet.MERKLE_DISTRIBUTOR
        );
        morphoMarketProxy.initialize(address(morphoMarket), Mainnet.TIMELOCK, data);

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Update OETH ARM to use Origin ARM contract");

        // 1. Transfer OETH out of the existing OETH ARM, to have a clean assets per share ratio.
        uint256 balanceOETH = IERC20(Mainnet.OETH).balanceOf(deployedContracts["OETH_ARM"]);
        govProposal.action(
            deployedContracts["OETH_ARM"],
            "transferToken(address,address,uint256)",
            abi.encode(Mainnet.OETH, Mainnet.TREASURY_LP, balanceOETH)
        );

        // 2. Transfer WETH out of the existing OETH ARM, to have a clean assets per share ratio.
        uint256 balanceWETH = IERC20(Mainnet.WETH).balanceOf(deployedContracts["OETH_ARM"]);
        govProposal.action(
            deployedContracts["OETH_ARM"],
            "transferToken(address,address,uint256)",
            abi.encode(Mainnet.WETH, Mainnet.TREASURY_LP, balanceWETH)
        );

        // 3. Timelock needs to approve the OETH ARM to pull WETH for initialization.
        govProposal.action(Mainnet.WETH, "approve(address,uint256)", abi.encode(deployedContracts["OETH_ARM"], 1e12));

        // 4. Upgrade the OETH ARM implementation, and initialize.
        bytes memory initializeData = abi.encodeWithSelector(
            OriginARM.initialize.selector,
            "Origin ARM",
            "ARM-WETH-OETH",
            Mainnet.ARM_RELAYER,
            2000, // 20% performance fee
            Mainnet.BUYBACK_OPERATOR, // Fee collector
            address(0)
        );

        // 5. Upgrade OETH ARM to OriginARM and call initialize
        govProposal.action(
            deployedContracts["OETH_ARM"],
            "upgradeToAndCall(address,bytes)",
            abi.encode(deployedContracts["OETH_ARM_IMPL"], initializeData)
        );

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

        // 8. Set crossPrice to 0.9995 ETH
        uint256 crossPrice = 0.9995 * 1e36;
        govProposal.action(deployedContracts["OETH_ARM"], "setCrossPrice(uint256)", abi.encode(crossPrice));

        govProposal.simulate();
    }
}
