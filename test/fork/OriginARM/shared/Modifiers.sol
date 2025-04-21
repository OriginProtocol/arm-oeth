// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Base_Test_} from "test/Base.sol";

contract Modifiers is Base_Test_ {
    ////////////////////////////////////////////////////
    /// --- SETTERS
    ////////////////////////////////////////////////////
    modifier addMarket(address market) {
        address[] memory markets = new address[](1);
        markets[0] = market;
        vm.startPrank(governor);
        originARM.addMarkets(markets);
        vm.stopPrank();
        _;
    }

    modifier setActiveMarket(address market) {
        vm.startPrank(governor);
        originARM.setActiveMarket(market);
        vm.stopPrank();
        _;
    }

    modifier setARMBuffer(uint256 buffer) {
        vm.startPrank(governor);
        originARM.setARMBuffer(buffer);
        vm.stopPrank();
        _;
    }
}
