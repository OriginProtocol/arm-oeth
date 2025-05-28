// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "forge-std/console.sol";

import {CapManager} from "contracts/CapManager.sol";
import {SonicHarvester} from "contracts/SonicHarvester.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {ZapperARM} from "contracts/ZapperARM.sol";
import {SiloMarket} from "contracts/markets/SiloMarket.sol";
import {Sonic} from "contracts/utils/Addresses.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract UpgradeSonicHarvesterScript is AbstractDeployScript {
    string public constant override DEPLOY_NAME = "003_UpgradeSonicHarvesterScript";
    bool public constant override proposalExecuted = false;

    Proxy public harvesterProxy;

    constructor(address _harvesterProxy) {
        require(_harvesterProxy != address(0), "Invalid proxy address");
        harvesterProxy = Proxy(payable(_harvesterProxy));
    }

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy the SonicHarvester implementation
        SonicHarvester harvesterImpl = new SonicHarvester(Sonic.WS);
        _recordDeploy("HARVESTER_IMPL", address(harvesterImpl));

        // 17. Upgrade Proxy to the new SonicHarvester implementation
        harvesterProxy.upgradeTo(address(harvesterImpl));

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _buildGovernanceProposal() internal override {}

    function _fork() internal view override {
        if (this.isForked()) {}
    }
}
