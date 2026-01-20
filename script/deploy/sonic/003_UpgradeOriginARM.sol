// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract imports
import {SonicHarvester} from "contracts/SonicHarvester.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {SiloMarket} from "contracts/markets/SiloMarket.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Sonic} from "contracts/utils/Addresses.sol";

// Deployment imports
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract UpgradeOriginARMScript is AbstractDeployScript("003_UpgradeOriginARMScript") {
    bool public override skip = false;
    bool public constant override proposalExecuted = true;

    SonicHarvester public harvesterImpl;
    OriginARM public originARMImpl;
    SiloMarket public silo_Varlamore_S_MarketImpl;

    function _execute() internal override {
        Proxy originARMProxy = Proxy(payable(resolver.implementations("ORIGIN_ARM")));

        // 1. Deploy the SonicHarvester implementation
        harvesterImpl = new SonicHarvester(Sonic.WS);
        _recordDeployment("HARVESTER_IMPL", address(harvesterImpl));

        // 2. Deploy new Origin ARM implementation
        uint256 claimDelay = 10 minutes;
        uint256 minSharesToRedeem = 1e7;
        int256 allocateThreshold = 1e18;
        originARMImpl =
            new OriginARM(Sonic.OS, Sonic.WS, Sonic.OS_VAULT, claimDelay, minSharesToRedeem, allocateThreshold);
        _recordDeployment("ORIGIN_ARM_IMPL", address(originARMImpl));

        // 3. Deploy the Silo market implementation for the Varlamore S Vault
        silo_Varlamore_S_MarketImpl =
            new SiloMarket(address(originARMProxy), Sonic.SILO_VARLAMORE_S_VAULT, Sonic.SILO_VARLAMORE_S_GAUGE);
        _recordDeployment("SILO_VARLAMORE_S_MARKET_IMPL", address(silo_Varlamore_S_MarketImpl));
    }

    function _fork() internal override {
        Proxy harvesterProxy = Proxy(payable(resolver.implementations("HARVESTER")));
        Proxy originARMProxy = Proxy(payable(resolver.implementations("ORIGIN_ARM")));
        Proxy silo_Varlamore_S_MarketProxy = Proxy(payable(resolver.implementations("SILO_VARLAMORE_S_MARKET")));

        vm.startPrank(Sonic.ADMIN);

        // 1. Upgrade SonicHarvester Proxy to the new implementation
        harvesterProxy.upgradeTo(address(harvesterImpl));

        // 2. Upgrade OriginARM Proxy to the new implementation
        originARMProxy.upgradeTo(address(originARMImpl));

        vm.stopPrank();

        vm.prank(Sonic.TIMELOCK);

        // 3. Upgrade SiloMarket Proxy to the new implementation
        silo_Varlamore_S_MarketProxy.upgradeTo(address(silo_Varlamore_S_MarketImpl));
    }
}
