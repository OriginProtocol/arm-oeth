// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AbstractARM} from "contracts/AbstractARM.sol";
import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";

contract Unit_Concrete_OriginARM_Pause_Test_ is Unit_Shared_Test {
    function test_Pause_ByOperator() public {
        vm.expectEmit(address(originARM));
        emit AbstractARM.Paused(operator);

        vm.prank(operator);
        originARM.pause();

        assertEq(originARM.paused(), true, "ARM should be paused");
    }

    function test_Pause_ByGovernor() public {
        vm.expectEmit(address(originARM));
        emit AbstractARM.Paused(governor);

        vm.prank(governor);
        originARM.pause();

        assertEq(originARM.paused(), true, "ARM should be paused");
    }

    function test_RevertWhen_Pause_Because_NotOperatorNorGovernor() public asNotOperatorNorGovernor {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        originARM.pause();
    }

    function test_Unpause_ByGovernor() public {
        vm.prank(operator);
        originARM.pause();

        vm.expectEmit(address(originARM));
        emit AbstractARM.Unpaused(governor);

        vm.prank(governor);
        originARM.unpause();

        assertEq(originARM.paused(), false, "ARM should be unpaused");
    }

    function test_RevertWhen_Unpause_Because_Operator() public {
        vm.prank(operator);
        originARM.pause();

        vm.prank(operator);
        vm.expectRevert("ARM: Only owner can call this function.");
        originARM.unpause();
    }

    function test_RevertWhen_Unpause_Because_RandomCaller() public asNotOperatorNorGovernor {
        vm.expectRevert("ARM: Only owner can call this function.");
        originARM.unpause();
    }

    function test_RevertWhen_Deposit_Because_Paused() public {
        _pause();
        deal(address(weth), alice, DEFAULT_AMOUNT);

        vm.startPrank(alice);
        weth.approve(address(originARM), DEFAULT_AMOUNT);
        vm.expectRevert("ARM: paused");
        originARM.deposit(DEFAULT_AMOUNT);
        vm.stopPrank();
    }

    function test_RevertWhen_DepositToReceiver_Because_Paused() public {
        _pause();
        deal(address(weth), alice, DEFAULT_AMOUNT);

        vm.startPrank(alice);
        weth.approve(address(originARM), DEFAULT_AMOUNT);
        vm.expectRevert("ARM: paused");
        originARM.deposit(DEFAULT_AMOUNT, bob);
        vm.stopPrank();
    }

    function test_RevertWhen_RequestRedeem_Because_Paused() public deposit(alice, DEFAULT_AMOUNT) {
        vm.prank(operator);
        originARM.pause();

        vm.prank(alice);
        vm.expectRevert("ARM: paused");
        originARM.requestRedeem(DEFAULT_AMOUNT);
    }

    function test_RevertWhen_SwapExactTokensForTokens_Sig1_Because_Paused() public {
        _pause();
        deal(address(oeth), alice, DEFAULT_AMOUNT);

        vm.startPrank(alice);
        oeth.approve(address(originARM), DEFAULT_AMOUNT);
        vm.expectRevert("ARM: paused");
        originARM.swapExactTokensForTokens(oeth, weth, DEFAULT_AMOUNT, 0, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_SwapExactTokensForTokens_Sig2_Because_Paused() public {
        _pause();
        deal(address(oeth), alice, DEFAULT_AMOUNT);
        address[] memory path = _path(address(oeth), address(weth));

        vm.startPrank(alice);
        oeth.approve(address(originARM), DEFAULT_AMOUNT);
        vm.expectRevert("ARM: paused");
        originARM.swapExactTokensForTokens(DEFAULT_AMOUNT, 0, path, alice, block.timestamp + 1);
        vm.stopPrank();
    }

    function test_RevertWhen_SwapTokensForExactTokens_Sig1_Because_Paused() public {
        _pause();
        deal(address(oeth), alice, DEFAULT_AMOUNT);

        vm.startPrank(alice);
        oeth.approve(address(originARM), DEFAULT_AMOUNT);
        vm.expectRevert("ARM: paused");
        originARM.swapTokensForExactTokens(oeth, weth, 1e12, DEFAULT_AMOUNT, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_SwapTokensForExactTokens_Sig2_Because_Paused() public {
        _pause();
        deal(address(oeth), alice, DEFAULT_AMOUNT);
        address[] memory path = _path(address(oeth), address(weth));

        vm.startPrank(alice);
        oeth.approve(address(originARM), DEFAULT_AMOUNT);
        vm.expectRevert("ARM: paused");
        originARM.swapTokensForExactTokens(1e12, DEFAULT_AMOUNT, path, alice, block.timestamp + 1);
        vm.stopPrank();
    }

    function test_ClaimRedeem_WhenPaused() public deposit(alice, DEFAULT_AMOUNT) {
        vm.prank(alice);
        originARM.requestRedeem(DEFAULT_AMOUNT);

        _pause();
        vm.warp(block.timestamp + CLAIM_DELAY);

        vm.prank(alice);
        vm.expectEmit(address(originARM));
        emit AbstractARM.RedeemClaimed(alice, 0, DEFAULT_AMOUNT);
        originARM.claimRedeem(0);
    }

    function test_CollectFees_WhenPaused() public {
        uint256 amountOut = 1e12;
        deal(address(weth), address(originARM), DEFAULT_AMOUNT);
        deal(address(oeth), alice, DEFAULT_AMOUNT);

        vm.startPrank(alice);
        oeth.approve(address(originARM), DEFAULT_AMOUNT);
        originARM.swapTokensForExactTokens(oeth, weth, amountOut, DEFAULT_AMOUNT, alice);
        vm.stopPrank();

        uint256 fees = originARM.feesAccrued();
        _pause();

        vm.expectEmit(address(originARM));
        emit AbstractARM.FeeCollected(feeCollector, fees);
        originARM.collectFees();
    }

    function test_OperationalFunctions_WhenPaused() public {
        _pause();

        uint256 crossPrice = _crossPrice();
        vm.prank(operator);
        vm.expectEmit(address(originARM));
        emit AbstractARM.TraderateChanged(address(oeth), crossPrice - 1, crossPrice);
        originARM.setPrices(address(oeth), crossPrice - 1, crossPrice, 2 ether, 3 ether);

        vm.prank(operator);
        vm.expectEmit(address(originARM));
        emit AbstractARM.ARMBufferUpdated(0);
        originARM.setARMBuffer(0);

        address[] memory markets = new address[](1);
        markets[0] = address(market);
        vm.prank(governor);
        originARM.addMarkets(markets);

        vm.prank(operator);
        vm.expectEmit(address(originARM));
        emit AbstractARM.ActiveMarketUpdated(address(market));
        originARM.setActiveMarket(address(market));

        deal(address(weth), address(originARM), DEFAULT_AMOUNT);
        originARM.allocate();
    }

    function test_BaseAssetRedeemAndClaim_WhenPaused() public {
        deal(address(oeth), address(originARM), DEFAULT_AMOUNT);
        deal(address(weth), address(vault), DEFAULT_AMOUNT);
        _pause();

        vm.prank(operator);
        originARM.requestBaseAssetRedeem(address(oeth), DEFAULT_AMOUNT);
        (,,,,, uint120 pendingRedeemAssets,,) = originARM.baseAssetConfigs(address(oeth));
        assertEq(pendingRedeemAssets, DEFAULT_AMOUNT, "Pending redeem assets");

        vm.prank(operator);
        (,, uint256 assetsReceived) = originARM.claimBaseAssetRedeem(address(oeth), DEFAULT_AMOUNT);
        assertEq(assetsReceived, DEFAULT_AMOUNT, "Assets received");
    }

    function _pause() internal {
        vm.prank(operator);
        originARM.pause();
    }

    function _path(address inToken, address outToken) internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = inToken;
        path[1] = outToken;
    }
}
