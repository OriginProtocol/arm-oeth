// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Helpers} from "test/unit/shared/Helpers.sol";

contract Modifiers is Helpers {
    modifier setDefaultStrategy() {
        vm.startPrank(governor);
        originARM.addMarket(address(market));
        originARM.setActiveMarket(address(market));
        originARM.setARMBuffer(1e18);
        vm.stopPrank();
        _;
    }

    modifier deposit(address user, uint256 amount) {
        vm.startPrank(user);
        deal(address(weth), user, amount);
        weth.approve(address(originARM), amount);
        originARM.deposit(amount);
        vm.stopPrank();
        _;
    }

    modifier asGovernor() {
        vm.startPrank(governor);
        _;
        vm.stopPrank();
    }

    modifier asNotGovernor() {
        vm.startPrank(randomAddrDiff(governor));
        _;
        vm.stopPrank();
    }
}
