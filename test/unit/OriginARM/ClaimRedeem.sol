// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";

contract Unit_Concrete_OriginARM_ClaimRedeem_Test_ is Unit_Shared_Test {
    uint256 internal constant LEGACY_PACKED_WITHDRAW_QUEUE_SLOT = 53;
    uint256 internal constant NEXT_WITHDRAWAL_INDEX_SLOT = 54;
    uint256 internal constant WITHDRAWAL_REQUESTS_SLOT = 55;

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
        assertFalse(originARM.isClaimable(0), "not mature");
        vm.expectRevert(bytes4(keccak256("ClaimDelayNotMet()")));
        originARM.claimRedeem(0);
    }

    function test_RevertWhen_ClaimRedeem_Because_QueuePendingLiquidity()
        public
        swapAllWETHForOETH
        requestRedeemAll(alice)
        timejump(CLAIM_DELAY)
    {
        vm.expectRevert(bytes4(keccak256("QueuePendingLiquidity()")));
        originARM.claimRedeem(0);
    }

    function test_ClaimRedeem_WhenSupportedBaseAssetDonationReducesShareFrontier()
        public
        requestRedeemAll(alice)
        timejump(CLAIM_DELAY)
    {
        deal(address(oeth), address(originARM), MIN_TOTAL_SUPPLY + 1e7);

        (uint256 claimableAssets, uint256 claimableShares) = originARM.claimable();
        assertLt(claimableShares, DEFAULT_AMOUNT, "share frontier");
        assertEq(claimableAssets, DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, "asset frontier");
        assertTrue(originARM.isClaimable(0), "is claimable");

        uint256 aliceBalanceBefore = weth.balanceOf(alice);

        vm.prank(alice);
        uint256 assets = originARM.claimRedeem(0);

        assertEq(assets, DEFAULT_AMOUNT, "claimed assets");
        assertEq(weth.balanceOf(alice), aliceBalanceBefore + DEFAULT_AMOUNT, "alice WETH");
        assertEq(originARM.reservedWithdrawLiquidity(), 0, "reserved liquidity");
        assertEq(originARM.withdrawsClaimedAssets(), DEFAULT_AMOUNT, "claimed asset caps");
        assertEq(originARM.withdrawsClaimedShares(), DEFAULT_AMOUNT, "claimed shares");
    }

    function test_ClaimRedeem_WhenDiscountedBaseAssetBuyReducesShareFrontier()
        public
        requestRedeemAll(alice)
        timejump(CLAIM_DELAY)
    {
        address swapper = makeAddr("swapper");
        deal(address(oeth), swapper, 1 ether);

        vm.startPrank(swapper);
        oeth.approve(address(originARM), type(uint256).max);
        originARM.swapTokensForExactTokens(oeth, weth, MIN_TOTAL_SUPPLY, type(uint256).max, swapper);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(originARM)), DEFAULT_AMOUNT, "liquid WETH");
        (uint256 claimableAssets, uint256 claimableShares) = originARM.claimable();
        assertLt(claimableShares, DEFAULT_AMOUNT, "share frontier");
        assertEq(claimableAssets, DEFAULT_AMOUNT, "asset frontier");
        assertTrue(originARM.isClaimable(0), "is claimable");

        uint256 aliceBalanceBefore = weth.balanceOf(alice);

        vm.prank(alice);
        uint256 assets = originARM.claimRedeem(0);

        assertEq(assets, DEFAULT_AMOUNT, "claimed assets");
        assertEq(weth.balanceOf(alice), aliceBalanceBefore + DEFAULT_AMOUNT, "alice WETH");
        assertEq(originARM.reservedWithdrawLiquidity(), 0, "reserved liquidity");
        assertEq(originARM.withdrawsClaimedAssets(), DEFAULT_AMOUNT, "claimed asset caps");
        assertEq(originARM.withdrawsClaimedShares(), DEFAULT_AMOUNT, "claimed shares");
    }

    function test_RevertWhen_ClaimRedeem_Because_NotWithdrawer()
        public
        requestRedeemAll(alice)
        timejump(CLAIM_DELAY)
        asNot(alice)
    {
        vm.expectRevert(bytes4(keccak256("NotRequesterOrOperator()")));
        originARM.claimRedeem(0);
    }

    function test_ClaimRedeem_WhenOperatorClaimsForWithdrawer() public requestRedeemAll(alice) timejump(CLAIM_DELAY) {
        uint256 aliceBalanceBefore = weth.balanceOf(alice);
        uint256 operatorBalanceBefore = weth.balanceOf(operator);

        vm.prank(operator);
        vm.expectEmit(address(originARM));
        emit AbstractARM.RedeemClaimed(alice, 0, DEFAULT_AMOUNT);
        originARM.claimRedeem(0);

        (, bool claimed,,,,) = originARM.withdrawalRequests(0);
        assertEq(claimed, true, "Claimed should be true");
        assertEq(originARM.reservedWithdrawLiquidity(), 0, "Reserved liquidity should be released");
        assertEq(originARM.withdrawsClaimedShares(), DEFAULT_AMOUNT, "Claimed shares should be DEFAULT_AMOUNT");
        assertEq(weth.balanceOf(alice), aliceBalanceBefore + DEFAULT_AMOUNT, "Alice should receive her WETH");
        assertEq(weth.balanceOf(operator), operatorBalanceBefore, "Operator should not receive WETH");
        (, uint256 claimableShares) = originARM.claimable();
        assertEq(claimableShares, DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, "Claimable should be updated");
    }

    function test_ClaimRedeem_WhenLegacyRequestClaimedByWithdrawer() public timejump(CLAIM_DELAY) {
        uint256 legacyRequestId = 1;
        uint128 legacyAssets = 0.4 ether;
        uint128 legacyShares = 0.5 ether;
        uint128 legacyQueued = 1 ether;
        uint128 legacyClaimed = legacyQueued - legacyAssets;
        _writeLegacyWithdrawQueue(legacyQueued, legacyClaimed);
        _writeLegacyWithdrawalRequest(
            legacyRequestId, alice, false, uint40(block.timestamp), legacyAssets, legacyQueued, legacyShares
        );
        _migrateWithLegacyBoundary(3);

        uint256 aliceBalanceBefore = weth.balanceOf(alice);
        uint256 armSharesBefore = originARM.balanceOf(address(originARM));

        vm.prank(alice);
        vm.expectEmit(address(originARM));
        emit AbstractARM.RedeemClaimed(alice, legacyRequestId, legacyAssets);
        originARM.claimRedeem(legacyRequestId);

        (, bool claimed,,,, uint256 shares) = originARM.withdrawalRequests(legacyRequestId);
        assertEq(claimed, true, "claimed");
        assertEq(shares, legacyShares, "legacy shares");
        assertEq(weth.balanceOf(alice), aliceBalanceBefore + legacyAssets, "alice WETH");
        assertEq(originARM.reservedWithdrawLiquidity(), 0, "reserved liquidity");
        assertEq(originARM.withdrawsClaimedShares(), 0, "claimed shares");
        assertEq(originARM.balanceOf(address(originARM)), armSharesBefore, "escrowed shares");
        assertEq(_readLegacyWithdrawQueue(), _packLegacyWithdrawQueue(legacyQueued, legacyQueued), "legacy claimed");
    }

    function test_ClaimRedeem_WhenLegacyRequestClaimedByOperator() public timejump(CLAIM_DELAY) {
        uint256 legacyRequestId = 2;
        uint128 legacyAssets = 0.25 ether;
        uint128 legacyShares = 0.3 ether;
        uint128 legacyQueued = 1 ether;
        uint128 legacyClaimed = legacyQueued - legacyAssets;
        _writeLegacyWithdrawQueue(legacyQueued, legacyClaimed);
        _writeLegacyWithdrawalRequest(
            legacyRequestId, alice, false, uint40(block.timestamp), legacyAssets, legacyQueued, legacyShares
        );
        _migrateWithLegacyBoundary(3);

        uint256 aliceBalanceBefore = weth.balanceOf(alice);
        uint256 operatorBalanceBefore = weth.balanceOf(operator);
        uint256 armSharesBefore = originARM.balanceOf(address(originARM));

        vm.prank(operator);
        originARM.claimRedeem(legacyRequestId);

        assertEq(weth.balanceOf(alice), aliceBalanceBefore + legacyAssets, "alice WETH");
        assertEq(weth.balanceOf(operator), operatorBalanceBefore, "operator WETH");
        assertEq(originARM.reservedWithdrawLiquidity(), 0, "reserved liquidity");
        assertEq(originARM.withdrawsClaimedShares(), 0, "claimed shares");
        assertEq(originARM.balanceOf(address(originARM)), armSharesBefore, "escrowed shares");
        assertEq(_readLegacyWithdrawQueue(), _packLegacyWithdrawQueue(legacyQueued, legacyQueued), "legacy claimed");
    }

    function test_ClaimRedeem_WhenRequestIdAtMigrationBoundaryUsesNewQueue() public timejump(CLAIM_DELAY) {
        _migrateWithLegacyBoundary(3);

        vm.prank(alice);
        (uint256 requestId,) = originARM.requestRedeem(DEFAULT_AMOUNT);
        assertEq(requestId, 3, "new request id");

        uint256 aliceBalanceBefore = weth.balanceOf(alice);
        uint256 armSharesBefore = originARM.balanceOf(address(originARM));

        vm.warp(block.timestamp + CLAIM_DELAY);
        vm.prank(alice);
        originARM.claimRedeem(requestId);

        assertEq(originARM.reservedWithdrawLiquidity(), 0, "reserved liquidity");
        assertEq(originARM.withdrawsClaimedShares(), DEFAULT_AMOUNT, "claimed shares");
        assertEq(originARM.balanceOf(address(originARM)), armSharesBefore - DEFAULT_AMOUNT, "escrowed shares burned");
        assertEq(weth.balanceOf(alice), aliceBalanceBefore + DEFAULT_AMOUNT, "alice WETH");
    }

    function test_RevertWhen_ClaimRedeem_Because_AlreadyClaimed() public requestRedeemAll(alice) timejump(CLAIM_DELAY) {
        // Alice claims her redeem
        vm.prank(alice);
        originARM.claimRedeem(0);
        assertFalse(originARM.isClaimable(0), "already claimed");

        // Attempt to claim again
        vm.prank(alice);
        vm.expectRevert(bytes4(keccak256("AlreadyClaimed()")));
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
        assertEq(originARM.reservedWithdrawLiquidity(), 0, "Reserved liquidity should be released");
        assertEq(originARM.withdrawsClaimedShares(), DEFAULT_AMOUNT, "Claimed shares should be DEFAULT_AMOUNT");
        assertEq(weth.balanceOf(alice), balanceBefore + DEFAULT_AMOUNT, "Alice should receive her WETH");
        (, uint256 claimableShares) = originARM.claimable();
        assertEq(claimableShares, DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, "Claimable should be updated");
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
        assertEq(originARM.reservedWithdrawLiquidity(), 0, "Reserved liquidity should be released");
        assertEq(originARM.withdrawsClaimedShares(), DEFAULT_AMOUNT, "Claimed shares should be DEFAULT_AMOUNT");
        assertEq(weth.balanceOf(alice), balanceBefore + DEFAULT_AMOUNT, "Alice should receive her WETH");
        (, uint256 claimableShares) = originARM.claimable();
        assertEq(claimableShares, DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, "Claimable should be updated");
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
        assertEq(originARM.reservedWithdrawLiquidity(), 0, "Reserved liquidity should be released");
        assertEq(originARM.withdrawsClaimedShares(), DEFAULT_AMOUNT, "Claimed shares should be DEFAULT_AMOUNT");
        assertEq(weth.balanceOf(alice), balanceBefore + DEFAULT_AMOUNT, "Alice should receive her WETH");
        (, uint256 claimableShares) = originARM.claimable();
        assertEq(claimableShares, DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, "Claimable should be updated");
    }

    function _writeLegacyWithdrawQueue(uint128 legacyQueued, uint128 legacyClaimed) internal {
        vm.store(
            address(originARM),
            bytes32(LEGACY_PACKED_WITHDRAW_QUEUE_SLOT),
            bytes32(_packLegacyWithdrawQueue(legacyQueued, legacyClaimed))
        );
    }

    function _writeLegacyWithdrawalRequest(
        uint256 requestId,
        address withdrawer,
        bool claimed,
        uint40 claimTimestamp,
        uint128 assets,
        uint128 queued,
        uint128 shares
    ) internal {
        bytes32 requestSlot = keccak256(abi.encode(requestId, WITHDRAWAL_REQUESTS_SLOT));
        uint256 slot0 =
            uint256(uint160(withdrawer)) | (claimed ? uint256(1) << 160 : 0) | (uint256(claimTimestamp) << 168);

        vm.store(address(originARM), requestSlot, bytes32(slot0));
        vm.store(
            address(originARM), bytes32(uint256(requestSlot) + 1), bytes32(uint256(assets) | (uint256(queued) << 128))
        );
        vm.store(address(originARM), bytes32(uint256(requestSlot) + 2), bytes32(uint256(shares)));
    }

    function _migrateWithLegacyBoundary(uint256 nextWithdrawalIndex) internal {
        vm.store(address(originARM), bytes32(NEXT_WITHDRAWAL_INDEX_SLOT), bytes32(nextWithdrawalIndex));

        vm.prank(governor);
        originARM.migrateLegacyWithdrawQueue();

        assertEq(originARM.legacyWithdrawalRequestCount(), nextWithdrawalIndex, "legacy request count");
    }

    function _readLegacyWithdrawQueue() internal view returns (uint256) {
        return uint256(vm.load(address(originARM), bytes32(LEGACY_PACKED_WITHDRAW_QUEUE_SLOT)));
    }

    function _packLegacyWithdrawQueue(uint128 legacyQueued, uint128 legacyClaimed) internal pure returns (uint256) {
        return uint256(legacyQueued) | (uint256(legacyClaimed) << 128);
    }
}
