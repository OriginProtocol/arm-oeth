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

    //////////////////////////////////////////////////////
    /// --- state machine integration
    //////////////////////////////////////////////////////

    /// @notice End-to-end state-machine check across two requests with progressive finalization
    ///         and three sequential claims. Catches integration-level bugs that the isolated
    ///         partial-drain / stops-at-unfinalized / claimableRedeem tests can't, because here
    ///         every state transition must compose with the next one — `nextPendingIndex` must
    ///         advance exactly, mappings must clear at the right moment, and `claimableRedeem`
    ///         must track finalization toggles in both directions.
    function test_StateMachine_MultiRequestMixedFinalization() public {
        // --- Setup: two requests, three queue ids (0 from req1, 1+2 from req2).
        vm.startPrank(address(lidoARM));
        stETHAssetAdapter.requestRedeem(500 ether); // id 0
        stETHAssetAdapter.requestRedeem(1_500 ether); // ids 1 and 2 (chunks 1000 + 500)
        vm.stopPrank();
        assertEq(stETHAssetAdapter.pendingRequestIdsLength(), 3, "3 queue ids registered");

        uint256 id0 = stETHAssetAdapter.pendingRequestId(0);
        uint256 id1 = stETHAssetAdapter.pendingRequestId(1);
        uint256 id2 = stETHAssetAdapter.pendingRequestId(2);

        // --- Roll id 1 back to un-finalized; id 0 and id 2 stay finalized.
        // This shape (finalized, NOT-finalized, finalized) is the strongest test for the
        // adapter's "stop at first non-finalized" rule: id 2 is finalizable but unreachable
        // until id 1 catches up, because claims are strictly FIFO.
        lidoWithdrawalQueue.mock_setFinalized(id1, false);

        // Stage 1: claimable should include id 0 only (loop breaks at id 1).
        {
            (uint256 cShares, uint256 cAssets) = stETHAssetAdapter.claimableRedeem();
            assertEq(cShares, 500 ether, "stage1 claimable shares == id0");
            assertEq(cAssets, 500 ether, "stage1 claimable assets == id0");
        }

        // Stage 2: redeem id 0; mappings for id 0 clear, id 1 and id 2 mappings untouched.
        vm.prank(address(lidoARM));
        (uint256 sc1,, uint256 ar1) = stETHAssetAdapter.redeem(500 ether);
        assertEq(sc1, 500 ether, "stage2 sharesClaimed");
        assertEq(ar1, 500 ether, "stage2 assetsReceived");
        assertEq(stETHAssetAdapter.requestShares(id0), 0, "id0 mapping cleared");
        assertEq(stETHAssetAdapter.requestShares(id1), 1_000 ether, "id1 mapping intact");
        assertEq(stETHAssetAdapter.requestShares(id2), 500 ether, "id2 mapping intact");
        // The pendingRequestIds array is append-only; only the read cursor advances.
        assertEq(stETHAssetAdapter.pendingRequestIdsLength(), 3, "pendingIds length still 3");

        // Stage 3: with id 1 still un-finalized, claimable == 0 even though id 2 IS finalized.
        // This is the FIFO property: id 2 cannot be skipped over id 1.
        {
            (uint256 cShares, uint256 cAssets) = stETHAssetAdapter.claimableRedeem();
            assertEq(cShares, 0, "stage3 claimable shares == 0 (id1 blocks id2)");
            assertEq(cAssets, 0, "stage3 claimable assets == 0");
        }

        // Stage 4: any redeem attempt now reverts on the FIFO check.
        vm.prank(address(lidoARM));
        vm.expectRevert("Adapter: redeem exceeds claimable");
        stETHAssetAdapter.redeem(1_000 ether);

        // Stage 5: finalize id 1. claimable jumps to id 1 + id 2 in a single step.
        lidoWithdrawalQueue.mock_setFinalized(id1, true);
        {
            (uint256 cShares, uint256 cAssets) = stETHAssetAdapter.claimableRedeem();
            assertEq(cShares, 1_500 ether, "stage5 claimable shares == id1 + id2");
            assertEq(cAssets, 1_500 ether, "stage5 claimable assets == id1 + id2");
        }

        // Stage 6: redeem id 1 alone (not id 1 + id 2 together). Cursor advances by exactly one.
        vm.prank(address(lidoARM));
        stETHAssetAdapter.redeem(1_000 ether);
        assertEq(stETHAssetAdapter.requestShares(id1), 0, "id1 mapping cleared");
        assertEq(stETHAssetAdapter.requestShares(id2), 500 ether, "id2 mapping intact after id1 claim");

        // Stage 7: claim id 2. Adapter is fully drained but the array remains length 3.
        vm.prank(address(lidoARM));
        stETHAssetAdapter.redeem(500 ether);
        assertEq(stETHAssetAdapter.requestShares(id2), 0, "id2 mapping cleared");
        {
            (uint256 cShares, uint256 cAssets) = stETHAssetAdapter.claimableRedeem();
            assertEq(cShares, 0, "stage7 claimable shares == 0 (drained)");
            assertEq(cAssets, 0, "stage7 claimable assets == 0");
        }
        assertEq(stETHAssetAdapter.pendingRequestIdsLength(), 3, "pendingIds length unchanged after full drain");

        // Stage 8: any further redeem reverts with the empty-queue message (cursor == length).
        vm.prank(address(lidoARM));
        vm.expectRevert("Adapter: no pending requests");
        stETHAssetAdapter.redeem(1 ether);
    }
}
