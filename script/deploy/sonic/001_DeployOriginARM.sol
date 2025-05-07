// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {CapManager} from "contracts/CapManager.sol";
import {Harvester} from "contracts/Harvester.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {ZapperARM} from "contracts/ZapperARM.sol";
import {SiloMarket} from "contracts/markets/SiloMarket.sol";
import {Sonic} from "contracts/utils/Addresses.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract DeployOriginARMScript is AbstractDeployScript {
    string public constant override DEPLOY_NAME = "001_DeployOriginARMScript";
    bool public constant override proposalExecuted = false;

    Proxy capManProxy;
    CapManager capManager;
    Proxy originARMProxy;
    OriginARM originARMImpl;
    OriginARM originARM;
    ZapperARM zapper;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy proxy for the Origin ARM
        originARMProxy = new Proxy();
        _recordDeploy("ORIGIN_ARM", address(originARMProxy));

        // 2. Deploy proxy for the CapManager
        capManProxy = new Proxy();
        _recordDeploy("ORIGIN_ARM_CAP_MAN", address(capManProxy));

        // 3. Deploy CapManager implementation
        CapManager capManagerImpl = new CapManager(address(originARMProxy));
        _recordDeploy("ORIGIN_ARM_CAP_IMPL", address(capManagerImpl));

        // 4. Initialize Proxy with CapManager implementation and set the owner to the deployer for now
        bytes memory data = abi.encodeWithSignature("initialize(address)", Sonic.RELAYER);
        capManProxy.initialize(address(capManagerImpl), deployer, data);
        capManager = CapManager(address(capManProxy));

        // 5. Set total wS cap
        capManager.setTotalAssetsCap(20000 ether);

        // 6. Transfer ownership of CapManager to the Sonic 5/8 Admin multisig
        capManProxy.setOwner(Sonic.ADMIN);

        // 7. Deploy new Origin ARM implementation
        uint256 claimDelay = tenderlyTestnet ? 1 minutes : 10 minutes;
        originARMImpl = new OriginARM(Sonic.OS, Sonic.WS, Sonic.OS_VAULT, claimDelay);
        _recordDeploy("ORIGIN_ARM_IMPL", address(originARMImpl));

        // 8. Approve a little bit of wS to be transferred to the ARM proxy
        // This is needed for the initialize function which will mint some ARM LP tokens
        // and send to a dead address
        IERC20(Sonic.WS).approve(address(originARMProxy), 1e12);

        // 9. Initialize Proxy with Origin ARM implementation and set the owner to the deployer for now
        data = abi.encodeWithSignature(
            "initialize(string,string,address,uint256,address,address)",
            "Origin ARM",
            "ARM-WS-OS",
            Sonic.RELAYER,
            2000, // 20% fee
            Sonic.STRATEGIST,
            address(capManProxy)
        );
        originARMProxy.initialize(address(originARMImpl), deployer, data);
        originARM = OriginARM(address(originARMProxy));

        // 10. Deploy the Silo market proxies
        Proxy silo_Varlamore_S_MarketProxy = new Proxy();
        _recordDeploy("SILO_VARLAMORE_S_MARKET", address(silo_Varlamore_S_MarketProxy));

        // 11. Deploy the Silo market implementations
        SiloMarket silo_Varlamore_S_MarketImpl =
            new SiloMarket(address(originARM), Sonic.SILO_VARLAMORE_S_VAULT, Sonic.SILO_VARLAMORE_S_GAUGE);
        _recordDeploy("SILO_VARLAMORE_S_MARKET_IMPL", address(silo_Varlamore_S_MarketImpl));

        // 12. Initialize Silo market Proxies, setting governor to Timelock and set Harvester to Relayer for now
        data = abi.encodeWithSignature("initialize(address)", Sonic.RELAYER);
        silo_Varlamore_S_MarketProxy.initialize(address(silo_Varlamore_S_MarketImpl), Sonic.TIMELOCK, data);

        // 13. Set the supported lending markets
        address[] memory markets = new address[](1);
        // These both have gauges so using a market proxy
        markets[0] = address(silo_Varlamore_S_MarketProxy);
        originARM.addMarkets(markets);

        // 14. Transfer ownership of OriginARM to the Sonic 5/8 Admin multisig
        originARM.setOwner(Sonic.ADMIN);

        // 15. Deploy the Zapper
        zapper = new ZapperARM(Sonic.WS);
        zapper.setOwner(Sonic.ADMIN);
        _recordDeploy("ARM_ZAPPER", address(zapper));

        // 15. Deploy the Harvester proxy
        Proxy harvesterProxy = new Proxy();
        _recordDeploy("HARVESTER", address(harvesterProxy));

        // 16. Deploy the Harvester implementation
        Harvester harvesterImpl = new Harvester(Sonic.WS, Sonic.MAGPIE_ROUTER);
        _recordDeploy("HARVESTER_IMPL", address(harvesterImpl));

        // 17. Initialize Proxy with Harvester implementation and set the owner to the deployer for now
        address PriceProvider = address(0);
        data =
            abi.encodeWithSignature("initialize(address,uint256,address)", PriceProvider, 200, address(originARMProxy));
        harvesterProxy.initialize(address(harvesterImpl), deployer, data);
        Harvester harvester = Harvester(address(harvesterProxy));

        // 18. Set the supported Silo market strategies
        harvester.setSupportedStrategy(address(silo_Varlamore_S_MarketProxy), true);

        // 19. Transfer ownership of Harvester to the Sonic 5/8 Admin multisig
        harvesterProxy.setOwner(Sonic.ADMIN);

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _buildGovernanceProposal() internal override {}

    function _fork() internal view override {
        if (this.isForked()) {}
    }
}
