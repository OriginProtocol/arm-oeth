// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "forge-std/console.sol";

import {OriginARM} from "contracts/OriginARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Sonic} from "contracts/utils/Addresses.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract UpgradeOriginARMSetBufferScript is AbstractDeployScript {
    string public constant override DEPLOY_NAME = "005_UpgradeOriginARMSetBufferScript";
    bool public constant override proposalExecuted = false;

    Proxy public originARMProxy;
    OriginARM public originARMImpl;

    constructor(address _originARMProxy) {
        require(_originARMProxy != address(0), "Invalid OriginARM proxy address");
        originARMProxy = Proxy(payable(_originARMProxy));
    }

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 2. Deploy new Origin ARM implementation
        uint256 claimDelay = tenderlyTestnet ? 1 minutes : 10 minutes;
        uint256 minSharesToRedeem = 1e7;
        int256 allocateThreshold = 1e18;
        originARMImpl =
            new OriginARM(Sonic.OS, Sonic.WS, Sonic.OS_VAULT, claimDelay, minSharesToRedeem, allocateThreshold);
        _recordDeploy("ORIGIN_ARM_IMPL", address(originARMImpl));

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _buildGovernanceProposal() internal override {}

    function _fork() internal override {
        if (this.isForked()) {
            vm.startPrank(Sonic.TIMELOCK);

            // 1. Upgrade OriginARM Proxy to the new implementation
            originARMProxy.upgradeTo(address(originARMImpl));

            // 2. Kill cap manager
            OriginARM(address(originARMProxy)).setCapManager(address(0));

            vm.stopPrank();
        }
    }
}
