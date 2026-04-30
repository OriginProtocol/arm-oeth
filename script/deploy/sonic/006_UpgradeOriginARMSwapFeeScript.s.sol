// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Proxy} from "contracts/Proxy.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {Sonic} from "contracts/utils/Addresses.sol";

import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract $006_UpgradeOriginARMSwapFeeScript is AbstractDeployScript("006_UpgradeOriginARMSwapFeeScript") {
    bool public constant override skip = false;

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
        (bool success,) = address(proxy).call(abi.encodeWithSignature("collectFees()"));
        require(success, "Collect fees failed");
        proxy.upgradeTo(impl);
        vm.stopPrank();
    }
}
