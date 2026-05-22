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

    function test_RevertWhen_ClaimRedeem_Because_AlreadyClaimed() public requestRedeemAll(alice) timejump(CLAIM_DELAY) {
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

        (, bool claimed,,,,) = originARM.withdrawalRequests(0);
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

        (, bool claimed,,,,) = originARM.withdrawalRequests(0);
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

        (, bool claimed,,,,) = originARM.withdrawalRequests(0);
        // Assertions
        assertEq(claimed, true, "Claimed should be true");
        assertEq(originARM.withdrawsClaimed(), DEFAULT_AMOUNT, "Claimed amount should be DEFAULT_AMOUNT");
        assertEq(weth.balanceOf(alice), balanceBefore + DEFAULT_AMOUNT, "Alice should receive her WETH");
        assertEq(originARM.claimable(), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, "Claimable should be updated");
    }

    function test_ClaimRedeem_WithFee_AfterMarketRecoveryCollectsOnlyRecoveryGain()
        public
        addMarket(address(market))
        setActiveMarket(address(market))
        setARMBuffer(0)
    {
        deal(address(weth), alice, 2 * DEFAULT_AMOUNT);
        vm.startPrank(alice);
        weth.approve(address(originARM), type(uint256).max);
        originARM.deposit(2 * DEFAULT_AMOUNT);
        vm.stopPrank();
        originARM.allocate();

        uint256 aliceShares = originARM.balanceOf(alice);
        vm.prank(alice);
        (uint256 requestId, uint256 requestedAssets) = originARM.requestRedeem(aliceShares / 2);

        uint256 marketWethBeforeLoss = weth.balanceOf(address(market));
        vm.prank(address(market));
        weth.transfer(address(0x1), marketWethBeforeLoss / 10);

        vm.warp(block.timestamp + CLAIM_DELAY);
        vm.prank(alice);
        uint256 claimedAssets = originARM.claimRedeem(requestId);
        assertLt(claimedAssets, requestedAssets, "claim should be haircut after market loss");

        int128 lastAvailableAfterClaim = originARM.lastAvailableAssets();

        deal(address(weth), bob, DEFAULT_AMOUNT);
        vm.startPrank(bob);
        weth.approve(address(originARM), DEFAULT_AMOUNT);
        originARM.deposit(DEFAULT_AMOUNT);
        vm.stopPrank();

        uint256 donatedRecovery = marketWethBeforeLoss / 10;
        deal(address(weth), address(market), weth.balanceOf(address(market)) + donatedRecovery);

        uint256 feeBefore = weth.balanceOf(feeCollector);
        uint256 accruedFees = originARM.feesAccrued();
        assertGt(accruedFees, 0, "recovery should accrue a fee");
        assertLt(accruedFees, donatedRecovery, "fee must be less than gross recovery");

        originARM.collectFees();
        assertEq(weth.balanceOf(feeCollector), feeBefore + accruedFees, "collector receives accrued recovery fee");
        assertGt(originARM.lastAvailableAssets(), lastAvailableAfterClaim, "collection advances fee baseline");

        (, bool claimed,,,,) = originARM.withdrawalRequests(requestId);
        assertTrue(claimed, "Alice request remains claimed after fee collection");
        assertEq(originARM.withdrawsClaimed(), requestedAssets, "fee collection does not reopen queue accounting");
    }

}
