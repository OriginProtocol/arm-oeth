// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract imports
import {PendleOriginARMSY} from "contracts/pendle/PendleOriginARMSY.sol";

// Deployment imports
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract $004_DeployPendleAdaptorSonic is AbstractDeployScript("004_DeployPendleAdaptor") {
    function _execute() internal override {
        // 1. Deploy PendleOriginARMSY
        PendleOriginARMSY sy = new PendleOriginARMSY("SY ORIGIN ARM", "SY-ARM-WS-OS", resolver.resolve("ORIGIN_ARM"));
        _recordDeployment("PENDLE_ORIGIN_ARM_SY", address(sy));
    }
}
