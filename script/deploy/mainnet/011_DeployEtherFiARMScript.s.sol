// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {IWETH} from "contracts/Interfaces.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {ZapperARM} from "contracts/ZapperARM.sol";
import {EtherFiARM} from "contracts/EtherFiARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {EtherFiAssetAdapter} from "contracts/adapters/EtherFiAssetAdapter.sol";
import {WeETHAssetAdapter} from "contracts/adapters/WeETHAssetAdapter.sol";
import {MorphoMarket} from "contracts/markets/MorphoMarket.sol";
import {Abstract4626MarketWrapper} from "contracts/markets/Abstract4626MarketWrapper.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract $011_DeployEtherFiARMScript is AbstractDeployScript("011_DeployEtherFiARMScript") {
    function _execute() internal override {
        // 1. Deploy new ARM proxy contract
        Proxy armProxy = new Proxy();
        _recordDeployment("ETHER_FI_ARM", address(armProxy));

        // 2. Deploy proxy for the CapManager
        Proxy capManProxy = new Proxy();
        _recordDeployment("ETHER_FI_ARM_CAP_MAN", address(capManProxy));

        // 3. Deploy CapManager implementation
        CapManager capManagerImpl = new CapManager(address(armProxy));
        _recordDeployment("ETHER_FI_ARM_CAP_IMPL", address(capManagerImpl));

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

        // 6. Deploy new Ether.Fi implementation
        uint256 claimDelay = 10 minutes;
        EtherFiARM etherFiARMImpl = new EtherFiARM(
            Mainnet.EETH,
            Mainnet.WETH,
            Mainnet.ETHERFI_WITHDRAWAL,
            claimDelay,
            1e7, // minSharesToRedeem
            1e18, // allocateThreshold
            Mainnet.ETHERFI_WITHDRAWAL_NFT
        );
        _recordDeployment("ETHER_FI_ARM_IMPL", address(etherFiARMImpl));

        // 7. Give the deployer a tiny amount of WETH for the initialization
        // This can be skipped if the deployer already has WETH
        IWETH(Mainnet.WETH).deposit{value: 1e13}();
        IWETH(Mainnet.WETH).approve(address(armProxy), 1e13);

        // 8. Initialize proxy, set the owner to deployer, set the operator to the ARM Relayer
        bytes memory armData = abi.encodeWithSignature(
            "initialize(string,string,address,uint256,address,address)",
            "Ether.fi ARM", // name
            "ARM-WETH-eETH", // symbol
            Mainnet.ARM_RELAYER, // Operator
            2000, // 20% performance fee
            Mainnet.BUYBACK_OPERATOR, // Fee collector
            address(capManager)
        );
        armProxy.initialize(address(etherFiARMImpl), deployer, armData);

        // 9. Deploy a Zapper that can work with different ARMs on mainnet
        ZapperARM zapper = new ZapperARM(Mainnet.WETH);
        zapper.setOwner(Mainnet.STRATEGIST);
        _recordDeployment("ARM_ZAPPER", address(zapper));

        // 10. Deploy MorphoMarket proxy
        Proxy morphoMarketProxy = new Proxy();
        _recordDeployment("MORPHO_MARKET_ETHERFI", address(morphoMarketProxy));

        // 11. Deploy MorphoMarket
        MorphoMarket morphoMarket = new MorphoMarket(address(armProxy), Mainnet.MORPHO_MARKET_ETHERFI);
        _recordDeployment("MORPHO_MARKET_ETHERFI_IMPL", address(morphoMarket));

        // 12. Initialize MorphoMarket proxy with the implementation, Timelock as owner
        bytes memory data = abi.encodeWithSelector(
            Abstract4626MarketWrapper.initialize.selector, Mainnet.STRATEGIST, Mainnet.MERKLE_DISTRIBUTOR
        );
        morphoMarketProxy.initialize(address(morphoMarket), Mainnet.TIMELOCK, data);

        // 13. Deploy the eETH adapter and register eETH as the base asset.
        uint256 crossPrice = 0.9998 * 1e36;
        {
            EtherFiAssetAdapter adapter = new EtherFiAssetAdapter(
                address(armProxy),
                Mainnet.EETH,
                Mainnet.WETH,
                Mainnet.ETHERFI_WITHDRAWAL,
                Mainnet.ETHERFI_WITHDRAWAL_NFT
            );
            _recordDeployment("ETHER_FI_ARM_EETH_ADAPTER", address(adapter));
            EtherFiARM(payable(address(armProxy)))
                .addBaseAsset(
                    Mainnet.EETH,
                    address(adapter),
                    0.9997 * 1e36,
                    1e36,
                    type(uint128).max,
                    type(uint128).max,
                    crossPrice,
                    true
                );
        }

        // 14. Deploy the weETH adapter and register weETH as a non-pegged base asset.
        {
            WeETHAssetAdapter weethAdapter = new WeETHAssetAdapter(
                address(armProxy),
                Mainnet.WEETH,
                Mainnet.EETH,
                Mainnet.WETH,
                Mainnet.ETHERFI_WITHDRAWAL,
                Mainnet.ETHERFI_WITHDRAWAL_NFT
            );
            _recordDeployment("ETHER_FI_ARM_WEETH_ADAPTER", address(weethAdapter));
            EtherFiARM(payable(address(armProxy)))
                .addBaseAsset(
                    Mainnet.WEETH,
                    address(weethAdapter),
                    0.9997 * 1e36,
                    1e36,
                    type(uint128).max,
                    type(uint128).max,
                    crossPrice,
                    false
                );
        }

        // 15. Add Morpho Market as an active market
        address[] memory markets = new address[](1);
        markets[0] = address(morphoMarketProxy);
        EtherFiARM(payable(address(armProxy))).addMarkets(markets);

        // 16. Set Morpho Market as the active market
        EtherFiARM(payable(address(armProxy))).setActiveMarket(address(morphoMarketProxy));

        // 17. Set ARM buffer to 20%
        EtherFiARM(payable(address(armProxy))).setARMBuffer(0.2e18); // 20% buffer

        // 18. Transfer ownership of ARM to the 5/8 multisig
        armProxy.setOwner(Mainnet.GOV_MULTISIG);
    }
}
