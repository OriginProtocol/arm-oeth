// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Proxy} from "contracts/Proxy.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract DeployOriginARMProxyScript is AbstractDeployScript("001_DeployOriginARMProxyScript") {
    bool public override skip = false;
    bool public constant override proposalExecuted = true;

    function _execute() internal override {
        // 1. Deploy proxy for the Origin ARM
        Proxy originARMProxy = new Proxy();
        _recordDeployment("ORIGIN_ARM", address(originARMProxy));
    }
}
