// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry imports
import {console} from "forge-std/console.sol";

// Contract imports
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {MorphoMarket} from "contracts/markets/MorphoMarket.sol";
import {EthenaUnstaker} from "contracts/EthenaARM.sol";
import {IWETH, IStakedUSDe} from "contracts/Interfaces.sol";
import {Abstract4626MarketWrapper} from "contracts/markets/Abstract4626MarketWrapper.sol";

// Deployment imports
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract DeployEthenaARMScript is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "014_DeployEthenaARMScript";
    bool public constant override proposalExecuted = false;

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
        capManager.setTotalAssetsCap(100000 ether); // 100,000 USDe total cap
        capManager.setAccountCapEnabled(true);
        address[] memory lpAccounts = new address[](7);
        lpAccounts[0] = Mainnet.TREASURY_LP;
        lpAccounts[1] = 0x8ac3b96d118288427055ae7f62e407fC7c482F57;
        lpAccounts[2] = 0x49aFBb19ebAd01274707A7226A34D5297B6dAf75;
        lpAccounts[3] = 0xF2B8C142Edcf2f3Cc22665cCE863a7C9A3E9F156;
        lpAccounts[4] = 0x8fAEE3092ef992FC3BD5BdAF496C30a3Ae1066c6;
        lpAccounts[5] = 0xE6030d4E773888e1DfE4CC31DA6e05bfe53091ac;
        lpAccounts[6] = 0x86D888C3fA8A7F67452eF2Eccc1C5EE9751Ec8d6;
        capManager.setLiquidityProviderCaps(lpAccounts, 20000 ether); // 20,000 USDe cap each

        // 5. Transfer ownership of CapManager to the mainnet 5/8 multisig
        capManProxy.setOwner(Mainnet.GOV_MULTISIG);

        // 6. Deploy new Ethena implementation
        uint256 claimDelay = tenderlyTestnet ? 1 minutes : 10 minutes;
        armImpl = new EthenaARM(
            Mainnet.USDE,
            Mainnet.SUSDE,
            claimDelay,
            1e18, // minSharesToRedeem
            100e18 // allocateThreshold
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

        // 9. Set crossPrice to 0.999 USDe which is a 10 bps discount
        uint256 crossPrice = 0.999 * 1e36;
        EthenaARM(payable(address(armProxy))).setCrossPrice(crossPrice);

        // 10. Add Aave Market as an active market
        address[] memory markets = new address[](1);
        markets[0] = Mainnet.AAVE_USDE_VAULT;
        EthenaARM(payable(address(armProxy))).addMarkets(markets);

        // 11. Set Aave Market as the active market
        EthenaARM(payable(address(armProxy))).setActiveMarket(Mainnet.AAVE_USDE_VAULT);
        // 12. Set ARM buffer to 10%
        EthenaARM(payable(address(armProxy))).setARMBuffer(0.1e18); // 10% buffer

        // 13. Deploy Unstakers
        address[MAX_UNSTAKERS] memory unstakers = _deployUnstakers();

        // 18. Set Unstakers in the ARM
        EthenaARM(payable(address(armProxy))).setUnstakers(unstakers);

        // 14. Transfer ownership of ARM to the 5/8 multisig
        armProxy.setOwner(Mainnet.GOV_MULTISIG);

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _deployUnstakers() internal returns (address[MAX_UNSTAKERS] memory unstakers) {
        for (uint256 i = 0; i < MAX_UNSTAKERS; i++) {
            address unstaker = address(new EthenaUnstaker(payable(armProxy), IStakedUSDe(Mainnet.SUSDE)));
            unstakers[i] = address(unstaker);
            console.log("Deployed unstaker", i, address(unstaker));
        }
        return unstakers;
    }
}
