// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "forge-std/console.sol";

import {SonicHarvester} from "contracts/SonicHarvester.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {SiloMarket} from "contracts/markets/SiloMarket.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Sonic} from "contracts/utils/Addresses.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract SetHarvesterScript is AbstractDeployScript {
    string public constant override DEPLOY_NAME = "004_SetHarvesterScript";
    bool public constant override proposalExecuted = false;

    Proxy public harvesterProxy;
    Proxy public silo_Varlamore_S_MarketProxy;

    constructor(address _harvesterProxy, address _silo_Varlamore_S_MarketProxy) {
        require(_harvesterProxy != address(0), "Invalid proxy address");
        harvesterProxy = Proxy(payable(_harvesterProxy));

        require(_silo_Varlamore_S_MarketProxy != address(0), "Invalid Silo Varlamore S proxy address");
        silo_Varlamore_S_MarketProxy = Proxy(payable(_silo_Varlamore_S_MarketProxy));
    }

    function _execute() internal pure override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _buildGovernanceProposal() internal override {}

    function _fork() internal override {
        if (this.isForked()) {
            vm.startPrank(Sonic.TIMELOCK);

            SiloMarket siloMarket = SiloMarket(address(silo_Varlamore_S_MarketProxy));

            siloMarket.setHarvester(address(harvesterProxy));

            vm.stopPrank();
        }
    }
}
