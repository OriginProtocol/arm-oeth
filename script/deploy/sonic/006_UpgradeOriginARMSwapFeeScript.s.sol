// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {Proxy} from "contracts/Proxy.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {Sonic} from "contracts/utils/Addresses.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract $006_UpgradeOriginARMSwapFeeScript is AbstractDeployScript("006_UpgradeOriginARMSwapFeeScript") {
    bool public constant override skip = true;

    function _execute() internal override {
        uint256 claimDelay = 10 minutes;
        uint256 minSharesToRedeem = 1e7;
        int256 allocateThreshold = 1e18;
        OriginARM originARMImpl =
            new OriginARM(Sonic.OS, Sonic.WS, Sonic.OS_VAULT, claimDelay, minSharesToRedeem, allocateThreshold);
        _recordDeployment("ORIGIN_ARM_IMPL", address(originARMImpl));
    }

    function _fork() internal override {
        Proxy proxy = Proxy(payable(resolver.resolve("ORIGIN_ARM")));
        address impl = resolver.resolve("ORIGIN_ARM_IMPL");

        if (proxy.implementation() == impl) return;

        vm.startPrank(proxy.owner());
        // Legacy fees must be collected before the proxy switches to the new swap-only fee logic.
        OriginARM(payable(address(proxy))).collectFees();
        proxy.upgradeToAndCall(impl, abi.encodeWithSelector(OriginARM.migrateFeesAccrued.selector));
        vm.stopPrank();
    }
}
