// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Helpers} from "test/fork/OriginARM/shared/Helpers.sol";
import {IERC20} from "contracts/Interfaces.sol";

contract Modifiers is Helpers {
    ////////////////////////////////////////////////////
    /// --- PRANK
    ////////////////////////////////////////////////////
    modifier asGovernor() {
        vm.startPrank(governor);
        _;
        vm.stopPrank();
    }

    modifier asOperator() {
        vm.startPrank(operator);
        _;
        vm.stopPrank();
    }

    modifier asNotGovernor() {
        vm.startPrank(randomAddrDiff(governor));
        _;
        vm.stopPrank();
    }

    modifier asNotOperatorNorGovernor() {
        vm.startPrank(randomAddrDiff(governor, operator));
        _;
        vm.stopPrank();
    }

    modifier asRandomCaller() {
        vm.startPrank(vm.randomAddress());
        _;
        vm.stopPrank();
    }

    modifier asNot(address user) {
        vm.startPrank(randomAddrDiff(user));
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

    modifier setFee(uint256 fee) {
        vm.startPrank(governor);
        originARM.setFee(fee);
        vm.stopPrank();
        _;
    }

    ////////////////////////////////////////////////////
    /// --- ACTIONS
    ////////////////////////////////////////////////////
    modifier deposit(address user, uint256 amount) {
        vm.startPrank(user);
        deal(address(ws), user, amount);
        ws.approve(address(originARM), amount);
        originARM.deposit(amount);
        vm.stopPrank();
        _;
    }

    modifier requestOriginWithdrawal(uint256 amount) {
        vm.startPrank(governor);
        originARM.requestOriginWithdrawal(amount);
        vm.stopPrank();
        _;
    }

    modifier allocate() {
        originARM.allocate();
        _;
    }

    modifier donate(IERC20 token, address user, uint256 amount) {
        deal(address(token), address(this), amount);
        token.transfer(user, amount);
        _;
    }

    modifier swapAllWSForOS() {
        address swapper = makeAddr("swapper");
        deal(address(os), swapper, 1_000_000 ether);
        vm.startPrank(swapper);
        os.approve(address(originARM), type(uint256).max);
        originARM.swapTokensForExactTokens(os, ws, ws.balanceOf(address(originARM)), type(uint256).max, swapper);
        vm.stopPrank();
        _;
    }

    function _swapAllWSForOS() internal swapAllWSForOS {}

    modifier swapAllOSForWS() {
        address swapper = makeAddr("swapper");
        deal(address(ws), swapper, 1_000_000 ether);
        vm.startPrank(swapper);
        ws.approve(address(originARM), type(uint256).max);
        originARM.swapTokensForExactTokens(ws, os, os.balanceOf(address(originARM)), type(uint256).max, swapper);
        vm.stopPrank();
        _;
    }

    function _swapAllOSForWS() internal swapAllOSForWS {}
}
