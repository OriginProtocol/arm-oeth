// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {Proxy} from "contracts/Proxy.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract $001_DeployOriginARMProxy is AbstractDeployScript("001_DeployOriginARMProxyScript") {
    function _execute() internal override {
        // 1. Deploy proxy for the Origin ARM
        Proxy originARMProxy = new Proxy();
        _recordDeployment("ORIGIN_ARM", address(originARMProxy));
    }
}
