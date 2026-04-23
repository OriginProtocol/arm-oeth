// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {CurveSwapTarget} from "contracts/swappers/CurveSwapTarget.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract $027_DeployLidoCurveSwapTarget is AbstractDeployScript("027_DeployLidoCurveSwapTarget") {
    function _execute() internal override {
        CurveSwapTarget target = new CurveSwapTarget(Mainnet.CURVE_STETH_POOL);
        _recordDeployment("LIDO_CURVE_SWAP_TARGET", address(target));
    }

    function _fork() internal override {
        CurveSwapTarget target = CurveSwapTarget(resolver.resolve("LIDO_CURVE_SWAP_TARGET"));
        require(target.pool() == Mainnet.CURVE_STETH_POOL, "Wrong Curve pool");
    }
}
