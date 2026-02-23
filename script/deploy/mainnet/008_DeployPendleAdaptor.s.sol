// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {PendleOriginARMSY} from "contracts/pendle/PendleOriginARMSY.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract $008_DeployPendleAdaptor is AbstractDeployScript("008_DeployPendleAdaptor") {
    function _execute() internal override {
        // 1. Deploy PendleOriginARMSY
        PendleOriginARMSY sy = new PendleOriginARMSY("SY Lido ARM", "SY-ARM-WETH-stETH", resolver.resolve("LIDO_ARM"));
        _recordDeployment("PENDLE_ORIGIN_ARM_SY", address(sy));
    }
}
