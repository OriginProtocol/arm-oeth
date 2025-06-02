// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";

contract Unit_Concrete_OriginARM_ClaimRedeem_Test_ is Unit_Shared_Test {
    function setUp() public virtual override {
        super.setUp();

        // Give Alice some WETH
        deal(address(weth), alice, 1_000 * DEFAULT_AMOUNT);

        // Alice approve max WETH to the ARM
        vm.startPrank(alice);
        weth.approve(address(originARM), type(uint256).max);
        originARM.deposit(DEFAULT_AMOUNT);
        vm.stopPrank();
    }

    function test_RevertWhen_ClaimRedeem_Because_DelayNotMet() public requestRedeemAll(alice) {
        vm.expectRevert("Claim delay not met");
        originARM.claimRedeem(0);
    }

    function test_RevertWhen_ClaimRedeem_Because_QueuePendingLiquidity()
        public
        swapAllWETHForOETH
        requestRedeemAll(alice)
        timejump(CLAIM_DELAY)
    {
        vm.expectRevert("Queue pending liquidity");
        originARM.claimRedeem(0);
    }

    function test_RevertWhen_ClaimRedeem_Because_NotWithdrawer()
        public
        requestRedeemAll(alice)
        timejump(CLAIM_DELAY)
        asNot(alice)
    {
        vm.expectRevert("Not requester");
        originARM.claimRedeem(0);
    }

    function test_RevertWhen_ClaimRedeem_Because_AlreadyClaimed()
        public
        requestRedeemAll(alice)
        timejump(CLAIM_DELAY)
    {
        // Alice claims her redeem
        vm.prank(alice);
        originARM.claimRedeem(0);

        // Attempt to claim again
        vm.prank(alice);
        vm.expectRevert("Already claimed");
        originARM.claimRedeem(0);
    }

    function test_ClaimRedeem_WithoutActiveMarket() public requestRedeemAll(alice) timejump(CLAIM_DELAY) {
        uint256 balanceBefore = weth.balanceOf(alice);
        // Alice claims her redeem
        vm.prank(alice);
        vm.expectEmit(address(originARM));
        emit AbstractARM.RedeemClaimed(alice, 0, DEFAULT_AMOUNT);
        originARM.claimRedeem(0);

        (, bool claimed,,,) = originARM.withdrawalRequests(0);
        // Assertions
        assertEq(claimed, true, "Claimed should be true");
        assertEq(originARM.withdrawsClaimed(), DEFAULT_AMOUNT, "Claimed amount should be DEFAULT_AMOUNT");
        assertEq(weth.balanceOf(alice), balanceBefore + DEFAULT_AMOUNT, "Alice should receive her WETH");
        assertEq(originARM.claimable(), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, "Claimable should be updated");
    }

    function test_ClaimRedeem_WithActiveMarket_EnoughLiquidity()
        public
        setARMBuffer(1e18)
        addMarket(address(market))
        setActiveMarket(address(market))
        requestRedeemAll(alice)
        timejump(CLAIM_DELAY)
    {
        uint256 balanceBefore = weth.balanceOf(alice);
        // Alice claims her redeem
        vm.prank(alice);
        vm.expectEmit(address(originARM));
        emit AbstractARM.RedeemClaimed(alice, 0, DEFAULT_AMOUNT);
        originARM.claimRedeem(0);

        (, bool claimed,,,) = originARM.withdrawalRequests(0);
        // Assertions
        assertEq(claimed, true, "Claimed should be true");
        assertEq(originARM.withdrawsClaimed(), DEFAULT_AMOUNT, "Claimed amount should be DEFAULT_AMOUNT");
        assertEq(weth.balanceOf(alice), balanceBefore + DEFAULT_AMOUNT, "Alice should receive her WETH");
        assertEq(originARM.claimable(), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, "Claimable should be updated");
    }

    function test_ClaimRedeem_WithActiveMarket_NotEnoughLiquidity()
        public
        setARMBuffer(0)
        addMarket(address(market))
        setActiveMarket(address(market))
        requestRedeemAll(alice)
        timejump(CLAIM_DELAY)
    {
        uint256 balanceBefore = weth.balanceOf(alice);
        // Alice claims her redeem
        vm.prank(alice);
        vm.expectEmit(address(originARM));
        emit AbstractARM.RedeemClaimed(alice, 0, DEFAULT_AMOUNT);
        originARM.claimRedeem(0);

        (, bool claimed,,,) = originARM.withdrawalRequests(0);
        // Assertions
        assertEq(claimed, true, "Claimed should be true");
        assertEq(originARM.withdrawsClaimed(), DEFAULT_AMOUNT, "Claimed amount should be DEFAULT_AMOUNT");
        assertEq(weth.balanceOf(alice), balanceBefore + DEFAULT_AMOUNT, "Alice should receive her WETH");
        assertEq(originARM.claimable(), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, "Claimable should be updated");
    }
}
