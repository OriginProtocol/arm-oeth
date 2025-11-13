// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry imports
import {console} from "forge-std/console.sol";

// Contract imports
import {IWETH} from "contracts/Interfaces.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {IStakedUSDe} from "contracts/Interfaces.sol";
import {MorphoMarket} from "contracts/markets/MorphoMarket.sol";
import {EthenaUnstaker} from "contracts/EthenaARM.sol";
import {Abstract4626MarketWrapper} from "contracts/markets/Abstract4626MarketWrapper.sol";

// Deployment imports
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract DeployEthenaARMScript is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "014_DeployEthenaARMScript";
    bool public constant override proposalExecuted = true;

    Proxy morphoMarketProxy;
    EthenaARM armImpl;
    MorphoMarket morphoMarket;
    Proxy armProxy;

    uint256 public constant MAX_UNSTAKERS = 42;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy new ARM proxy contract
        armProxy = new Proxy();
        _recordDeploy("ETHENA_ARM", address(armProxy));

        // 2. Deploy proxy for the CapManager
        Proxy capManProxy = new Proxy();
        _recordDeploy("ETHENA_ARM_CAP_MAN", address(capManProxy));

        // 3. Deploy CapManager implementation
        CapManager capManagerImpl = new CapManager(address(armProxy));
        _recordDeploy("ETHENA_ARM_CAP_IMPL", address(capManagerImpl));

        // 4. Initialize Proxy with CapManager implementation and set the owner to the deployer for now
        bytes memory capManData = abi.encodeWithSignature("initialize(address)", Mainnet.ARM_RELAYER);
        capManProxy.initialize(address(capManagerImpl), deployer, capManData);
        CapManager capManager = CapManager(address(capManProxy));

        // 4. Set total assets and liquidity provider caps
        capManager.setTotalAssetsCap(250 ether);
        capManager.setAccountCapEnabled(true);
        address[] memory lpAccounts = new address[](1);
        lpAccounts[0] = Mainnet.TREASURY_LP;
        capManager.setLiquidityProviderCaps(lpAccounts, 250 ether);

        // 5. Transfer ownership of CapManager to the mainnet 5/8 multisig
        capManProxy.setOwner(Mainnet.GOV_MULTISIG);

        // 6. Deploy new Ethena implementation
        uint256 claimDelay = tenderlyTestnet ? 1 minutes : 10 minutes;
        armImpl = new EthenaARM(
            Mainnet.USDE,
            Mainnet.SUSDE,
            claimDelay,
            1e7, // minSharesToRedeem
            1e18 // allocateThreshold
        );
        _recordDeploy("ETHENA_ARM_IMPL", address(armImpl));

        // 7. Give the deployer a tiny amount of USDe for the initialization
        // This can be skipped if the deployer already has USDe
        IWETH(Mainnet.USDE).approve(address(armProxy), 1e13);

        // 8. Initialize proxy, set the owner to deployer, set the operator to the ARM Relayer
        bytes memory armData = abi.encodeWithSignature(
            "initialize(string,string,address,uint256,address,address)",
            "Ethena Staked USDe ARM", // name
            "ARM-sUSDe-USDe", // symbol
            Mainnet.ARM_RELAYER, // Operator
            2000, // 20% performance fee
            Mainnet.BUYBACK_OPERATOR, // Fee collector
            address(capManager)
        );
        armProxy.initialize(address(armImpl), deployer, armData);

        console.log("Initialized Ethena ARM");

        // 10. Deploy MorphoMarket proxy
        morphoMarketProxy = new Proxy();
        _recordDeploy("MORPHO_MARKET_ETHENA", address(morphoMarketProxy));

        // 11. Deploy MorphoMarket
        morphoMarket = new MorphoMarket(address(armProxy), Mainnet.MORPHO_MARKET_ETHENA);
        _recordDeploy("MORPHO_MARKET_ETHENA_IMPL", address(morphoMarket));

        // 12. Initialize MorphoMarket proxy with the implementation, Timelock as owner
        bytes memory data = abi.encodeWithSelector(
            Abstract4626MarketWrapper.initialize.selector, Mainnet.STRATEGIST, Mainnet.MERKLE_DISTRIBUTOR
        );
        morphoMarketProxy.initialize(address(morphoMarket), Mainnet.TIMELOCK, data);

        // 13. Set crossPrice to 0.9998 USDe
        uint256 crossPrice = 0.9998 * 1e36;
        EthenaARM(payable(address(armProxy))).setCrossPrice(crossPrice);

        // 14. Add Morpho Market as an active market
        address[] memory markets = new address[](1);
        markets[0] = address(morphoMarketProxy);
        EthenaARM(payable(address(armProxy))).addMarkets(markets);

        // 15. Set Morpho Market as the active market
        EthenaARM(payable(address(armProxy))).setActiveMarket(address(morphoMarketProxy));

        // 16. Set ARM buffer to 10%
        EthenaARM(payable(address(armProxy))).setARMBuffer(0.1e18); // 10% buffer

        // 17. Transfer ownership of ARM to the 5/8 multisig
        armProxy.setOwner(Mainnet.GOV_MULTISIG);

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function deployUnstakers() external returns (address[MAX_UNSTAKERS] memory unstakers) {
        for (uint256 i = 0; i < MAX_UNSTAKERS; i++) {
            address unstaker = address(new EthenaUnstaker(payable(armProxy), IStakedUSDe(Mainnet.SUSDE)));
            unstakers[i] = address(unstaker);
            console.log("Deployed unstaker", i, address(unstaker));
        }
        return unstakers;
    }
}
