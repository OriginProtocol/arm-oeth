// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_LidoARM_Shared_Test} from "../../Shared.t.sol";

// Contracts
import {AbstractLidoAssetAdapter} from "contracts/adapters/AbstractLidoAssetAdapter.sol";

/// @notice Direct unit tests for `AbstractLidoAssetAdapter` exercised through
///         `StETHAssetAdapter` (1:1 share/asset math). Covers the adapter
///         contract in isolation by pranking `address(lidoARM)` — the ARM-side
///         flow already has coverage in `BaseAssetRedeem.t.sol`.
contract Unit_LidoARM_StETHAssetAdapter_Test is Unit_LidoARM_Shared_Test {
    uint256 internal constant ARM_STETH_BALANCE = 5_000 ether;

    function setUp() public override {
        super.setUp();
        desactiveCapManager();
        // addBaseAsset registers the adapter and sets the ARM → adapter approval for stETH.
        addBaseAsset(steth);
        // Seed the ARM with enough stETH to cover the largest multi-chunk request in this file.
        deal(address(steth), address(lidoARM), ARM_STETH_BALANCE);
    }

    //////////////////////////////////////////////////////
    /// --- initialize / view / approvals
    //////////////////////////////////////////////////////
    function test_Initialize_RevertWhen_AlreadyInitialized() public {
        vm.expectRevert(); // OZ Initializable: InvalidInitialization
        stETHAssetAdapter.initialize();
    }

    function test_Asset_ReturnsWeth() public view {
        assertEq(stETHAssetAdapter.asset(), address(weth), "asset");
    }

    function test_StETHApprovalToQueueIsMax() public view {
        assertEq(
            steth.allowance(address(stETHAssetAdapter), address(lidoWithdrawalQueue)),
            type(uint256).max,
            "stETH allowance adapter -> queue"
        );
    }

    //////////////////////////////////////////////////////
    /// --- modifiers
    //////////////////////////////////////////////////////
    function test_RequestRedeem_RevertWhen_NotARM() public {
        vm.prank(alice);
        vm.expectRevert("Adapter: only ARM");
        stETHAssetAdapter.requestRedeem(1 ether);
    }

    function test_RequestRedeem_RevertWhen_ZeroShares() public {
        vm.prank(address(lidoARM));
        vm.expectRevert("Adapter: zero shares");
        stETHAssetAdapter.requestRedeem(0);
    }

    function test_Redeem_RevertWhen_NotARM() public {
        vm.prank(alice);
        vm.expectRevert("Adapter: only ARM");
        stETHAssetAdapter.redeem(1 ether);
    }

    function test_Redeem_RevertWhen_ZeroShares() public {
        vm.prank(address(lidoARM));
        vm.expectRevert("Adapter: zero shares");
        stETHAssetAdapter.redeem(0);
    }

    //////////////////////////////////////////////////////
    /// --- requestRedeem — single chunk
    //////////////////////////////////////////////////////
    function test_RequestRedeem_SingleChunk_500Ether() public {
        uint256 shares = 500 ether;

        // Pre
        assertEq(steth.balanceOf(address(lidoARM)), ARM_STETH_BALANCE, "ARM stETH pre");
        assertEq(steth.balanceOf(address(stETHAssetAdapter)), 0, "adapter stETH pre");
        assertEq(steth.balanceOf(address(lidoWithdrawalQueue)), 0, "queue stETH pre");
        assertEq(stETHAssetAdapter.pendingRequestIdsLength(), 0, "pendingIds pre");

        // When
        vm.prank(address(lidoARM));
        (uint256 sharesRequested, uint256 assetsExpected) = stETHAssetAdapter.requestRedeem(shares);

        // Then — return values (1:1 math)
        assertEq(sharesRequested, shares, "sharesRequested");
        assertEq(assetsExpected, shares, "assetsExpected");

        // stETH flowed ARM → withdrawal queue, adapter holds no residual stETH.
        assertEq(steth.balanceOf(address(lidoARM)), ARM_STETH_BALANCE - shares, "ARM stETH post");
        assertEq(steth.balanceOf(address(stETHAssetAdapter)), 0, "adapter stETH post");
        assertEq(steth.balanceOf(address(lidoWithdrawalQueue)), shares, "queue stETH post");

        // Adapter storage tracks the new request.
        assertEq(stETHAssetAdapter.pendingRequestIdsLength(), 1, "pendingIds post");
        uint256 id = stETHAssetAdapter.pendingRequestId(0);
        assertEq(stETHAssetAdapter.requestShares(id), shares, "requestShares");
        assertEq(stETHAssetAdapter.requestAssets(id), shares, "requestAssets");

        // Queue recorded the request against the adapter as the owner.
        (address owner, uint256 amount,, bool finalized) = lidoWithdrawalQueue.requests(id);
        assertEq(owner, address(stETHAssetAdapter), "request.owner");
        assertEq(amount, shares, "request.amount");
        assertTrue(finalized, "request.finalized");
    }

    function test_RequestRedeem_ExactBoundary_1000Ether() public {
        uint256 shares = 1_000 ether;

        vm.prank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(shares);

        // Exactly one chunk; no second request created.
        assertEq(stETHAssetAdapter.pendingRequestIdsLength(), 1, "single chunk at boundary");
        assertEq(lidoWithdrawalQueue.counter(), 1, "queue counter");

        uint256 id = stETHAssetAdapter.pendingRequestId(0);
        assertEq(stETHAssetAdapter.requestAssets(id), shares, "single chunk amount == request");
    }

    function test_RequestRedeem_JustAboveBoundary_1001Ether() public {
        uint256 shares = 1_001 ether;

        vm.prank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(shares);

        assertEq(stETHAssetAdapter.pendingRequestIdsLength(), 2, "two chunks above boundary");

        uint256 id0 = stETHAssetAdapter.pendingRequestId(0);
        uint256 id1 = stETHAssetAdapter.pendingRequestId(1);
        assertEq(stETHAssetAdapter.requestAssets(id0), 1_000 ether, "chunk0 amount");
        assertEq(stETHAssetAdapter.requestAssets(id1), 1 ether, "chunk1 amount");

        // Share splits sum back to total (1:1).
        assertEq(
            stETHAssetAdapter.requestShares(id0) + stETHAssetAdapter.requestShares(id1), shares, "share splits sum"
        );
    }

    function test_RequestRedeem_MultiChunk_2500Ether() public {
        uint256 shares = 2_500 ether;

        vm.prank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(shares);

        assertEq(stETHAssetAdapter.pendingRequestIdsLength(), 3, "three chunks");

        uint256 sumAssets;
        uint256 sumShares;
        uint256[3] memory expectedAmounts = [uint256(1_000 ether), uint256(1_000 ether), uint256(500 ether)];
        for (uint256 i; i < 3; ++i) {
            uint256 id = stETHAssetAdapter.pendingRequestId(i);
            assertEq(stETHAssetAdapter.requestAssets(id), expectedAmounts[i], "chunk amount");
            sumAssets += stETHAssetAdapter.requestAssets(id);
            sumShares += stETHAssetAdapter.requestShares(id);
        }
        assertEq(sumAssets, shares, "sum chunk amounts == request");
        assertEq(sumShares, shares, "sum chunk shares == request");
    }

    function test_RequestRedeem_TwoSequentialCalls() public {
        vm.startPrank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(300 ether);
        stETHAssetAdapter.requestRedeem(200 ether);
        vm.stopPrank();

        assertEq(stETHAssetAdapter.pendingRequestIdsLength(), 2, "pendingIds after two calls");
        uint256 id0 = stETHAssetAdapter.pendingRequestId(0);
        uint256 id1 = stETHAssetAdapter.pendingRequestId(1);
        assertTrue(id0 != id1, "ids distinct");
        assertEq(stETHAssetAdapter.requestAssets(id0), 300 ether, "first chunk");
        assertEq(stETHAssetAdapter.requestAssets(id1), 200 ether, "second chunk");
    }

    //////////////////////////////////////////////////////
    /// --- redeem — happy paths
    //////////////////////////////////////////////////////
    function test_Redeem_SingleRequest() public {
        uint256 shares = 500 ether;

        vm.startPrank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(shares);

        uint256 armWethBefore = weth.balanceOf(address(lidoARM));
        uint256 id = stETHAssetAdapter.pendingRequestId(0);

        // When
        (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived) = stETHAssetAdapter.redeem(shares);
        vm.stopPrank();

        // Return values
        assertEq(sharesClaimed, shares, "sharesClaimed");
        assertEq(assetsExpected, shares, "assetsExpected");
        assertEq(assetsReceived, shares, "assetsReceived");

        // WETH lands on the ARM; adapter holds no residual ETH or WETH.
        assertEq(weth.balanceOf(address(lidoARM)), armWethBefore + shares, "ARM weth post");
        assertEq(weth.balanceOf(address(stETHAssetAdapter)), 0, "adapter weth post");
        assertEq(address(stETHAssetAdapter).balance, 0, "adapter eth post");

        // Mappings cleared and the queue marked the request as claimed.
        assertEq(stETHAssetAdapter.requestShares(id), 0, "requestShares cleared");
        assertEq(stETHAssetAdapter.requestAssets(id), 0, "requestAssets cleared");
        (,, bool claimed,) = lidoWithdrawalQueue.requests(id);
        assertTrue(claimed, "queue.claimed");
    }

    function test_Redeem_MultipleRequests_FullDrain() public {
        vm.startPrank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(400 ether);
        stETHAssetAdapter.requestRedeem(600 ether);

        uint256 armWethBefore = weth.balanceOf(address(lidoARM));
        uint256 id0 = stETHAssetAdapter.pendingRequestId(0);
        uint256 id1 = stETHAssetAdapter.pendingRequestId(1);

        (uint256 sharesClaimed,, uint256 assetsReceived) = stETHAssetAdapter.redeem(1_000 ether);
        vm.stopPrank();

        assertEq(sharesClaimed, 1_000 ether, "sharesClaimed");
        assertEq(assetsReceived, 1_000 ether, "assetsReceived");
        assertEq(weth.balanceOf(address(lidoARM)), armWethBefore + 1_000 ether, "ARM weth post");

        // Both mappings cleared.
        assertEq(stETHAssetAdapter.requestShares(id0), 0, "id0 cleared");
        assertEq(stETHAssetAdapter.requestShares(id1), 0, "id1 cleared");
    }

    function test_Redeem_PartialDrain_FirstChunkOnly() public {
        // Single requestRedeem(2500) creates three chunks: 1000/1000/500.
        vm.startPrank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(2_500 ether);

        uint256 id0 = stETHAssetAdapter.pendingRequestId(0);
        uint256 id1 = stETHAssetAdapter.pendingRequestId(1);
        uint256 id2 = stETHAssetAdapter.pendingRequestId(2);
        uint256 armWethBefore = weth.balanceOf(address(lidoARM));

        // Redeem only the first chunk's shares.
        (uint256 sharesClaimed,, uint256 assetsReceived) = stETHAssetAdapter.redeem(1_000 ether);
        vm.stopPrank();

        assertEq(sharesClaimed, 1_000 ether, "sharesClaimed");
        assertEq(assetsReceived, 1_000 ether, "assetsReceived");
        assertEq(weth.balanceOf(address(lidoARM)), armWethBefore + 1_000 ether, "ARM weth post");

        // Only id0 cleared; id1 and id2 still queued.
        assertEq(stETHAssetAdapter.requestShares(id0), 0, "id0 cleared");
        assertEq(stETHAssetAdapter.requestShares(id1), 1_000 ether, "id1 retained");
        assertEq(stETHAssetAdapter.requestShares(id2), 500 ether, "id2 retained");

        // pendingRequestIds array length is unchanged; the index moved forward.
        assertEq(stETHAssetAdapter.pendingRequestIdsLength(), 3, "pendingIds length unchanged");
    }

    function test_Redeem_WrapsEthToWeth() public {
        uint256 shares = 750 ether;

        vm.startPrank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(shares);

        uint256 armWethBefore = weth.balanceOf(address(lidoARM));
        stETHAssetAdapter.redeem(shares);
        vm.stopPrank();

        assertEq(address(stETHAssetAdapter).balance, 0, "adapter eth post");
        assertEq(weth.balanceOf(address(stETHAssetAdapter)), 0, "adapter weth post");
        assertEq(weth.balanceOf(address(lidoARM)) - armWethBefore, shares, "ARM weth delta == eth received");
    }

    //////////////////////////////////////////////////////
    /// --- redeem — revert branch coverage
    //////////////////////////////////////////////////////
    function test_Redeem_RevertWhen_NoPendingRequests() public {
        vm.prank(address(lidoARM));
        vm.expectRevert("Adapter: no pending requests");
        stETHAssetAdapter.redeem(1 ether);
    }

    function test_Redeem_RevertWhen_FirstUnfinalized() public {
        vm.prank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(500 ether);

        uint256 id0 = stETHAssetAdapter.pendingRequestId(0);
        lidoWithdrawalQueue.mock_setFinalized(id0, false);

        vm.prank(address(lidoARM));
        vm.expectRevert("Adapter: redeem exceeds claimable");
        stETHAssetAdapter.redeem(500 ether);
    }

    function test_Redeem_RevertWhen_FirstAlreadyClaimed() public {
        vm.prank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(500 ether);

        uint256 id0 = stETHAssetAdapter.pendingRequestId(0);
        lidoWithdrawalQueue.mock_setClaimed(id0, true);

        vm.prank(address(lidoARM));
        vm.expectRevert("Adapter: redeem exceeds claimable");
        stETHAssetAdapter.redeem(500 ether);
    }

    function test_Redeem_RevertWhen_FirstOwnerChanged() public {
        vm.prank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(500 ether);

        uint256 id0 = stETHAssetAdapter.pendingRequestId(0);
        lidoWithdrawalQueue.mock_setOwner(id0, alice);

        vm.prank(address(lidoARM));
        vm.expectRevert("Adapter: redeem exceeds claimable");
        stETHAssetAdapter.redeem(500 ether);
    }

    function test_Redeem_StopsAtFirstUnfinalized() public {
        vm.startPrank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(300 ether);
        stETHAssetAdapter.requestRedeem(200 ether);
        vm.stopPrank();

        uint256 id1 = stETHAssetAdapter.pendingRequestId(1);
        lidoWithdrawalQueue.mock_setFinalized(id1, false);

        // Redeeming the first id's shares still succeeds; loop breaks before consuming id1.
        vm.prank(address(lidoARM));
        (uint256 sharesClaimed,,) = stETHAssetAdapter.redeem(300 ether);
        assertEq(sharesClaimed, 300 ether, "claimed first only");

        // Redeeming further reverts since id1 is still un-finalized.
        vm.prank(address(lidoARM));
        vm.expectRevert("Adapter: redeem exceeds claimable");
        stETHAssetAdapter.redeem(200 ether);
    }

    function test_Redeem_RevertWhen_InvalidRedeemAmount_FirstChunkOvershoots() public {
        // 1500 → chunks of 1000 + 500. Redeeming 700 overshoots the first chunk.
        vm.prank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(1_500 ether);

        vm.prank(address(lidoARM));
        vm.expectRevert("Adapter: invalid redeem amount");
        stETHAssetAdapter.redeem(700 ether);
    }

    function test_Redeem_RevertWhen_InvalidRedeemAmount_BetweenChunks() public {
        // 1500 → chunks of 1000 + 500. Redeeming 1200 lands between the two chunk totals.
        vm.prank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(1_500 ether);

        vm.prank(address(lidoARM));
        vm.expectRevert("Adapter: invalid redeem amount");
        stETHAssetAdapter.redeem(1_200 ether);
    }

    //////////////////////////////////////////////////////
    /// --- claimableRedeem
    //////////////////////////////////////////////////////
    function test_ClaimableRedeem_ZeroWhenEmpty() public view {
        (uint256 shares, uint256 assets) = stETHAssetAdapter.claimableRedeem();
        assertEq(shares, 0, "claimable shares");
        assertEq(assets, 0, "claimable assets");
    }

    function test_ClaimableRedeem_AllFinalized_ReturnsSum() public {
        vm.startPrank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(300 ether);
        stETHAssetAdapter.requestRedeem(200 ether);
        vm.stopPrank();

        (uint256 shares, uint256 assets) = stETHAssetAdapter.claimableRedeem();
        assertEq(shares, 500 ether, "claimable shares");
        assertEq(assets, 500 ether, "claimable assets");
    }

    function test_ClaimableRedeem_StopsAtFirstUnfinalized() public {
        vm.startPrank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(300 ether);
        stETHAssetAdapter.requestRedeem(200 ether);
        vm.stopPrank();

        uint256 id1 = stETHAssetAdapter.pendingRequestId(1);
        lidoWithdrawalQueue.mock_setFinalized(id1, false);

        (uint256 shares, uint256 assets) = stETHAssetAdapter.claimableRedeem();
        assertEq(shares, 300 ether, "claimable shares");
        assertEq(assets, 300 ether, "claimable assets");
    }

    function test_ClaimableRedeem_UpdatesAfterPartialRedeem() public {
        vm.startPrank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(300 ether);
        stETHAssetAdapter.requestRedeem(200 ether);

        // Drain the first request; nextPendingIndex advances by 1.
        stETHAssetAdapter.redeem(300 ether);
        vm.stopPrank();

        (uint256 shares, uint256 assets) = stETHAssetAdapter.claimableRedeem();
        assertEq(shares, 200 ether, "remaining claimable shares");
        assertEq(assets, 200 ether, "remaining claimable assets");
    }

    //////////////////////////////////////////////////////
    /// --- getters
    //////////////////////////////////////////////////////
    function test_PendingRequestIdsLength_GrowsWithRequests() public {
        assertEq(stETHAssetAdapter.pendingRequestIdsLength(), 0, "initial");

        vm.prank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(500 ether);
        assertEq(stETHAssetAdapter.pendingRequestIdsLength(), 1, "after single-chunk request");

        vm.prank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(1_500 ether);
        assertEq(stETHAssetAdapter.pendingRequestIdsLength(), 3, "after two-chunk request");
    }

    function test_PendingRequestId_IndexableAndOrdered() public {
        vm.prank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(2_500 ether);

        // Mock counter increments by one per chunk, so ids are 0,1,2 in order.
        assertEq(stETHAssetAdapter.pendingRequestId(0), 0, "id at index 0");
        assertEq(stETHAssetAdapter.pendingRequestId(1), 1, "id at index 1");
        assertEq(stETHAssetAdapter.pendingRequestId(2), 2, "id at index 2");
    }

    function test_PendingRequestId_RevertWhen_OutOfBounds() public {
        // Empty array — index 0 is out of bounds.
        vm.expectRevert();
        stETHAssetAdapter.pendingRequestId(0);
    }
}
