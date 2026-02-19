// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {PendleOriginARMSY} from "contracts/pendle/PendleOriginARMSY.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract $019_DeployPendleAdaptor_EtherFi is AbstractDeployScript("019_DeployPendleAdaptor_EtherFi") {
    function _execute() internal override {
        // 1. Deploy PendleOriginARMSY
        PendleOriginARMSY sy =
            new PendleOriginARMSY("SY EtherFi ARM", "SY-ARM-WETH-eETH", resolver.resolve("ETHER_FI_ARM"));
        _recordDeployment("PENDLE_ETHERFI_ARM_SY", address(sy));
    }
}
