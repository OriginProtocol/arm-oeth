// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Helpers} from "test/unit/shared/Helpers.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

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

    modifier setCapManager() {
        vm.startPrank(governor);
        originARM.setCapManager(address(capManager));
        vm.stopPrank();
        _;
    }

    modifier setTotalAssetsCapUnlimited() {
        vm.startPrank(governor);
        capManager.setTotalAssetsCap(type(uint248).max);
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
        deal(address(weth), user, amount);
        weth.approve(address(originARM), amount);
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

    modifier swapAllWETHForOETH() {
        address swapper = makeAddr("swapper");
        deal(address(oeth), swapper, 1_000_000 ether);
        vm.startPrank(swapper);
        oeth.approve(address(originARM), type(uint256).max);
        originARM.swapTokensForExactTokens(oeth, weth, weth.balanceOf(address(originARM)), type(uint256).max, swapper);
        vm.stopPrank();
        _;
    }

    modifier swapAllOETHForWETH() {
        address swapper = makeAddr("swapper");
        deal(address(weth), swapper, 1_000_000 ether);
        vm.startPrank(swapper);
        weth.approve(address(originARM), type(uint256).max);
        originARM.swapTokensForExactTokens(weth, oeth, oeth.balanceOf(address(originARM)), type(uint256).max, swapper);
        vm.stopPrank();
        _;
    }

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

    modifier allocate() {
        originARM.allocate();
        _;
    }

    modifier marketLoss(address market, uint256 lossPct) {
        uint256 balance = weth.balanceOf(market);
        uint256 amountToThrow = (balance * lossPct) / 1e18;
        vm.prank(market);
        weth.transfer(address(0x1), amountToThrow);
        _;
    }

    modifier donate(IERC20 token, address user, uint256 amount) {
        deal(address(token), address(this), amount);
        token.transfer(user, amount);
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
    modifier simulateMarketLoss(address market, uint256 lossPct) {
        uint256 maxWithdraw = IERC4626(market).maxWithdraw(address(originARM));
        uint256 maxRedeem = IERC4626(market).maxRedeem(address(originARM));
        uint256 lossOnWithdraw = lossPct == 1e18 ? 0 : (maxWithdraw * lossPct) / 1e18;
        uint256 lossOnRedeem = lossPct == 1e18 ? 0 : (maxRedeem * lossPct) / 1e18;
        vm.mockCall(market, abi.encodeWithSelector(IERC4626.maxWithdraw.selector), abi.encode(lossOnWithdraw));
        vm.mockCall(market, abi.encodeWithSelector(IERC4626.maxRedeem.selector), abi.encode(lossOnRedeem));
        _;
    }

    modifier timejump(uint256 secondsToJump) {
        vm.warp(block.timestamp + secondsToJump);
        _;
    }
}
