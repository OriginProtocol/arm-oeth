// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "forge-std/console.sol";

import {CapManager} from "contracts/CapManager.sol";
import {SonicHarvester} from "contracts/SonicHarvester.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {ZapperARM} from "contracts/ZapperARM.sol";
import {SiloMarket} from "contracts/markets/SiloMarket.sol";
import {Sonic} from "contracts/utils/Addresses.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract DeployOriginARMScript is AbstractDeployScript {
    string public constant override DEPLOY_NAME = "002_DeployOriginARMScript";
    bool public constant override proposalExecuted = true;

    Proxy public originARMProxy;

    constructor(address _originARMProxy) {
        require(_originARMProxy != address(0), "Invalid proxy address");
        originARMProxy = Proxy(payable(_originARMProxy));
    }

    Proxy capManProxy;
    CapManager capManager;
    OriginARM originARMImpl;
    OriginARM originARM;
    ZapperARM zapper;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy proxy for the CapManager
        capManProxy = new Proxy();
        _recordDeploy("ORIGIN_ARM_CAP_MAN", address(capManProxy));

        // 2. Deploy CapManager implementation
        CapManager capManagerImpl = new CapManager(address(originARMProxy));
        _recordDeploy("ORIGIN_ARM_CAP_IMPL", address(capManagerImpl));

        // 3. Initialize Proxy with CapManager implementation and set the owner to the deployer for now
        bytes memory data = abi.encodeWithSelector(CapManager.initialize.selector, Sonic.RELAYER);
        capManProxy.initialize(address(capManagerImpl), deployer, data);
        capManager = CapManager(address(capManProxy));

        // 4. Set total wS cap
        capManager.setTotalAssetsCap(200 ether);

        // 5. Transfer ownership of CapManager to the Sonic 5/8 Admin multisig
        capManProxy.setOwner(Sonic.ADMIN);

        // 6. Deploy new Origin ARM implementation
        uint256 claimDelay = tenderlyTestnet ? 1 minutes : 10 minutes;
        originARMImpl = new OriginARM(Sonic.OS, Sonic.WS, Sonic.OS_VAULT, claimDelay, 1e7, 1e18);
        _recordDeploy("ORIGIN_ARM_IMPL", address(originARMImpl));

        // 7. Approve a little bit of wS to be transferred to the ARM proxy
        // This is needed for the initialize function which will mint some ARM LP tokens
        // and send to a dead address
        IERC20(Sonic.WS).approve(address(originARMProxy), 1e12);

        // 8. Initialize Proxy with Origin ARM implementation and set the owner to the deployer for now
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

        // 9. Deploy the Silo market proxies
        Proxy silo_Varlamore_S_MarketProxy = new Proxy();
        _recordDeploy("SILO_VARLAMORE_S_MARKET", address(silo_Varlamore_S_MarketProxy));

        // 10. Deploy the Silo market implementations
        SiloMarket silo_Varlamore_S_MarketImpl =
            new SiloMarket(address(originARM), Sonic.SILO_VARLAMORE_S_VAULT, Sonic.SILO_VARLAMORE_S_GAUGE);
        _recordDeploy("SILO_VARLAMORE_S_MARKET_IMPL", address(silo_Varlamore_S_MarketImpl));

        // 11. Initialize Silo market Proxies, setting governor to Timelock and set Harvester to Relayer for now
        data = abi.encodeWithSignature("initialize(address)", Sonic.RELAYER);
        silo_Varlamore_S_MarketProxy.initialize(address(silo_Varlamore_S_MarketImpl), Sonic.TIMELOCK, data);

        // 12. Set the supported lending markets
        address[] memory markets = new address[](1);
        // These both have gauges so using a market proxy
        markets[0] = address(silo_Varlamore_S_MarketProxy);
        originARM.addMarkets(markets);

        // 13. Transfer ownership of OriginARM to the Sonic 5/8 Admin multisig
        originARM.setOwner(Sonic.ADMIN);

        // 14. Deploy the Zapper
        zapper = new ZapperARM(Sonic.WS);
        zapper.setOwner(Sonic.ADMIN);
        _recordDeploy("ORIGIN_ARM_ZAPPER", address(zapper));

        // 15. Deploy the SonicHarvester proxy
        Proxy harvesterProxy = new Proxy();
        _recordDeploy("HARVESTER", address(harvesterProxy));

        // 16. Deploy the SonicHarvester implementation
        SonicHarvester harvesterImpl = new SonicHarvester(Sonic.WS);
        _recordDeploy("HARVESTER_IMPL", address(harvesterImpl));

        // 17. Initialize Proxy with SonicHarvester implementation and set the owner to the deployer for now
        address PriceProvider = address(0);
        data = abi.encodeWithSignature(
            "initialize(address,uint256,address,address)",
            PriceProvider,
            200,
            address(originARMProxy),
            Sonic.MAGPIE_ROUTER
        );
        harvesterProxy.initialize(address(harvesterImpl), deployer, data);
        SonicHarvester harvester = SonicHarvester(address(harvesterProxy));

        // 18. Set the supported Silo market strategies
        harvester.setSupportedStrategy(address(silo_Varlamore_S_MarketProxy), true);

        // 19. Transfer ownership of SonicHarvester to the Sonic 5/8 Admin multisig
        harvesterProxy.setOwner(Sonic.ADMIN);

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _buildGovernanceProposal() internal override {}

    function _fork() internal view override {
        if (this.isForked()) {}
    }
}
