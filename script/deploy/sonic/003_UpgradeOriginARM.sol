// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "forge-std/console.sol";

import {SonicHarvester} from "contracts/SonicHarvester.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {SiloMarket} from "contracts/markets/SiloMarket.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Sonic} from "contracts/utils/Addresses.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract UpgradeOriginARMScript is AbstractDeployScript {
    string public constant override DEPLOY_NAME = "003_UpgradeOriginARMScriptScript";
    bool public constant override proposalExecuted = false;

    Proxy public harvesterProxy;
    SonicHarvester public harvesterImpl;
    Proxy public originARMProxy;
    OriginARM public originARMImpl;
    Proxy public silo_Varlamore_S_MarketProxy;
    SiloMarket public silo_Varlamore_S_MarketImpl;

    constructor(address _harvesterProxy, address _originARMProxy, address _silo_Varlamore_S_MarketProxy) {
        require(_harvesterProxy != address(0), "Invalid proxy address");
        harvesterProxy = Proxy(payable(_harvesterProxy));

        require(_originARMProxy != address(0), "Invalid OriginARM proxy address");
        originARMProxy = Proxy(payable(_originARMProxy));

        require(_silo_Varlamore_S_MarketProxy != address(0), "Invalid Silo Varlamore S proxy address");
        silo_Varlamore_S_MarketProxy = Proxy(payable(_silo_Varlamore_S_MarketProxy));
    }

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy the SonicHarvester implementation
        harvesterImpl = new SonicHarvester(Sonic.WS);
        _recordDeploy("HARVESTER_IMPL", address(harvesterImpl));

        // 2. Deploy new Origin ARM implementation
        uint256 claimDelay = tenderlyTestnet ? 1 minutes : 10 minutes;
        uint256 minSharesToRedeem = 1e7;
        int256 allocateThreshold = 1e18;
        originARMImpl =
            new OriginARM(Sonic.OS, Sonic.WS, Sonic.OS_VAULT, claimDelay, minSharesToRedeem, allocateThreshold);
        _recordDeploy("ORIGIN_ARM_IMPL", address(originARMImpl));

        // 3. Deploy the Silo market implementation for the Varlamore S Vault
        silo_Varlamore_S_MarketImpl =
            new SiloMarket(address(originARMProxy), Sonic.SILO_VARLAMORE_S_VAULT, Sonic.SILO_VARLAMORE_S_GAUGE);
        _recordDeploy("SILO_VARLAMORE_S_MARKET_IMPL", address(silo_Varlamore_S_MarketImpl));

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _buildGovernanceProposal() internal override {}

    function _fork() internal override {
        if (this.isForked()) {
            vm.startPrank(Sonic.ADMIN);

            // 1. Upgrade SonicHarvester Proxy to the new implementation
            harvesterProxy.upgradeTo(address(harvesterImpl));

            // 2. Upgrade OriginARM Proxy to the new implementation
            originARMProxy.upgradeTo(address(originARMImpl));

            // 3. Upgrade SiloMarket Proxy to the new implementation
            silo_Varlamore_S_MarketProxy.upgradeTo(address(silo_Varlamore_S_MarketImpl));

            vm.stopPrank();
        }
    }
}
