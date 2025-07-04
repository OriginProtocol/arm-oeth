// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Helpers} from "test/fork/OriginARM/shared/Helpers.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {ISilo, Silo} from "test/fork/OriginARM/shared/ISilo.sol";

contract Modifiers is Helpers {
    Silo public silo;
    Silo public SILO_OS = Silo(payable(0x1d7E3726aFEc5088e11438258193A199F9D5Ba93));
    Silo public SILO_WS = Silo(payable(0x112380065A2cb73A5A429d9Ba7368cc5e8434595)); // == market

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

    modifier requestRedeem(address user, uint256 pct) {
        uint256 shares = originARM.balanceOf(alice);
        vm.prank(alice);
        originARM.requestRedeem((shares * pct) / 1e18);
        _;
    }

    modifier requestRedeemAll(address user) {
        uint256 shares = originARM.balanceOf(user);
        vm.prank(user);
        originARM.requestRedeem(shares);
        _;
    }

    modifier timejump(uint256 secondsToJump) {
        vm.warp(block.timestamp + secondsToJump);
        _;
    }

    modifier marketUtilizedAt(uint256 utilization) {
        ISilo.UtilizationData memory utilizationBefore = SILO_WS.utilizationData();
        uint256 availableLiquidity = utilizationBefore.collateralAssets - utilizationBefore.debtAssets;

        // Deposit WOS in the Silo 0
        uint256 wosToDeposit = availableLiquidity * 2;
        deal(address(wos), address(this), wosToDeposit);
        wos.approve(address(SILO_OS), type(uint256).max);
        SILO_OS.deposit(wosToDeposit, address(this), ISilo.CollateralType.Protected);

        // Borrow WS in the Silo 1
        uint256 wsToBorrow = availableLiquidity * utilization / 1e18;
        SILO_WS.borrow(wsToBorrow, address(this), address(this));
        _;
    }

    function _marketUtilizedAt(uint256 utilization) internal marketUtilizedAt(utilization) {}
}
