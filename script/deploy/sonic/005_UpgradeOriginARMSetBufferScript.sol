// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract imports
import {OriginARM} from "contracts/OriginARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Sonic} from "contracts/utils/Addresses.sol";

// Deployment imports
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract UpgradeOriginARMSetBufferScript is AbstractDeployScript("005_UpgradeOriginARMSetBufferScript") {
    bool public override skip = false;
    bool public constant override proposalExecuted = false;

    OriginARM public originARMImpl;

    function _execute() internal override {
        // 1. Deploy new Origin ARM implementation
        uint256 claimDelay = 10 minutes;
        uint256 minSharesToRedeem = 1e7;
        int256 allocateThreshold = 1e18;
        originARMImpl =
            new OriginARM(Sonic.OS, Sonic.WS, Sonic.OS_VAULT, claimDelay, minSharesToRedeem, allocateThreshold);
        _recordDeployment("ORIGIN_ARM_IMPL", address(originARMImpl));
    }

    function _fork() internal override {
        Proxy originARMProxy = Proxy(payable(resolver.implementations("ORIGIN_ARM")));

        vm.startPrank(Sonic.TIMELOCK);

        // 1. Upgrade OriginARM Proxy to the new implementation
        originARMProxy.upgradeTo(address(originARMImpl));

        // 2. Kill cap manager
        OriginARM(address(originARMProxy)).setCapManager(address(0));

        vm.stopPrank();
    }
}
