// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Base_Test_} from "test/Base.sol";

contract Modifiers is Base_Test_ {
    modifier setDefaultStrategy() {
        vm.startPrank(governor);
        originARM.addStrategy(address(strategy));
        originARM.setDefaultStrategy(address(strategy));
        originARM.setArmBuffer(1e18);
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
}
