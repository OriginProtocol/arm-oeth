// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Helpers} from "test/unit/shared/Helpers.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

contract Modifiers is Helpers {
    using stdStorage for StdStorage;

    ////////////////////////////////////////////////////
    /// --- PRANK
    ////////////////////////////////////////////////////
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

    ////////////////////////////////////////////////////
    /// --- ACTIONS
    ////////////////////////////////////////////////////
    modifier deposit(address user, uint256 amount) {
        vm.startPrank(user);
        deal(address(weth), user, amount);
        weth.approve(address(originARM), amount);
        originARM.deposit(amount);
        vm.stopPrank();
        _;
    }

    /// @dev Cheat function to force available assets in the ARM to be 0
    /// Send OETH and WETH to address(0x1)
    /// Write directly in the storage of the ARM the vaultWithdrawalAmount to 0
    modifier forceAvailableAssetsToZero() {
        vm.startPrank(address(originARM));
        oeth.transfer(address(0x1), oeth.balanceOf(address(originARM)));
        weth.transfer(address(0x1), weth.balanceOf(address(originARM)));
        stdstore.target(address(originARM)).sig("vaultWithdrawalAmount()").checked_write(uint256(0));
        vm.stopPrank();
        _;
    }

    ////////////////////////////////////////////////////
    /// --- MOCK CALLS
    ////////////////////////////////////////////////////
}
