// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_LidoARM_Shared_Test} from "../../Shared.t.sol";

/// @notice Non-1:1 unit tests for `AbstractLidoAssetAdapter` exercised through
///         `WstETHAssetAdapter`. Coverage of the wrap/unwrap path and the
///         `_splitShares` arithmetic that only matters when 1 share != 1 asset.
///         The fixture seeds the wrapper so 1 wstETH = 1.237 stETH.
///
///         NOTE: `_splitShares` contains a `splitShares == 0` fallback for ratios
///         where the per-chunk share amount rounds down to zero. That branch is
///         unreachable with a stETH-per-wstETH rate > 1 and is therefore not
///         covered here.
contract Unit_LidoARM_WstETHAssetAdapter_Test is Unit_LidoARM_Shared_Test {
    uint256 internal constant ARM_WSTETH_BALANCE = 5_000 ether;

    function setUp() public override {
        super.setUp();
        desactiveCapManager();
        // 1 wstETH = 1.237 stETH after seeding. Must run BEFORE dealWsteth so the
        // exchange rate is set when the helper computes the stETH required to mint.
        seedWstETHWithTargetExchangeRate();
        addBaseAsset(wsteth);
        dealWsteth(address(lidoARM), ARM_WSTETH_BALANCE);
    }

    //////////////////////////////////////////////////////
    /// --- sanity
    //////////////////////////////////////////////////////
    function test_Asset_ReturnsWeth() public view {
        assertEq(wstETHAssetAdapter.asset(), address(weth), "asset");
    }

    function test_StETHApprovalToQueueIsMax() public view {
        assertEq(
            steth.allowance(address(wstETHAssetAdapter), address(lidoWithdrawalQueue)),
            type(uint256).max,
            "stETH allowance adapter -> queue"
        );
    }

    //////////////////////////////////////////////////////
    /// --- requestRedeem — non-1:1 conversion
    //////////////////////////////////////////////////////
    function test_RequestRedeem_NonOneToOne_SingleChunk() public {
        uint256 shares = 100 ether; // 100 wstETH
        uint256 expectedStETH = 123.7 ether; // 100 * 1.237

        // Pre
        assertEq(wsteth.balanceOf(address(lidoARM)), ARM_WSTETH_BALANCE, "ARM wstETH pre");
        assertEq(steth.balanceOf(address(lidoWithdrawalQueue)), 0, "queue stETH pre");

        // When
        vm.prank(address(lidoARM));
        (uint256 sharesRequested, uint256 assetsExpected) = wstETHAssetAdapter.requestRedeem(shares);

        // Return values: shares are wstETH; assets are stETH (the asset the queue receives).
        assertEq(sharesRequested, shares, "sharesRequested");
        assertEq(assetsExpected, expectedStETH, "assetsExpected (stETH)");

        // Token flow: ARM lost wstETH; adapter holds no residual wstETH or stETH;
        // queue received the unwrapped stETH amount.
        assertEq(wsteth.balanceOf(address(lidoARM)), ARM_WSTETH_BALANCE - shares, "ARM wstETH post");
        assertEq(wsteth.balanceOf(address(wstETHAssetAdapter)), 0, "adapter wstETH post");
        assertEq(steth.balanceOf(address(wstETHAssetAdapter)), 0, "adapter stETH post");
        assertEq(steth.balanceOf(address(lidoWithdrawalQueue)), expectedStETH, "queue stETH post");

        // Storage: single chunk records full shares against the stETH amount.
        assertEq(wstETHAssetAdapter.pendingRequestIdsLength(), 1, "pendingIds");
        uint256 id = wstETHAssetAdapter.pendingRequestId(0);
        assertEq(wstETHAssetAdapter.requestShares(id), shares, "requestShares");
        assertEq(wstETHAssetAdapter.requestAssets(id), expectedStETH, "requestAssets");
    }

    function test_RequestRedeem_NonOneToOne_MultiChunk() public {
        // 900 wstETH → 1113.3 stETH → two chunks of 1000 + 113.3.
        uint256 shares = 900 ether;
        uint256 expectedStETH = 1_113.3 ether;

        vm.prank(address(lidoARM));
        (, uint256 assetsExpected) = wstETHAssetAdapter.requestRedeem(shares);
        assertEq(assetsExpected, expectedStETH, "assetsExpected total");

        assertEq(wstETHAssetAdapter.pendingRequestIdsLength(), 2, "two chunks");
        uint256 id0 = wstETHAssetAdapter.pendingRequestId(0);
        uint256 id1 = wstETHAssetAdapter.pendingRequestId(1);

        // Asset amounts: capped at MAX_WITHDRAWAL_AMOUNT then the remainder.
        assertEq(wstETHAssetAdapter.requestAssets(id0), 1_000 ether, "chunk0 stETH");
        assertEq(wstETHAssetAdapter.requestAssets(id1), 113.3 ether, "chunk1 stETH");

        // _splitShares: per-chunk share count rounds down; the final chunk absorbs
        // the rounding remainder. The invariant is `sum(shareSplits) == totalShares`.
        uint256 s0 = wstETHAssetAdapter.requestShares(id0);
        uint256 s1 = wstETHAssetAdapter.requestShares(id1);
        assertGt(s0, 0, "chunk0 shares non-zero");
        assertGt(s1, 0, "chunk1 shares non-zero");
        assertEq(s0 + s1, shares, "share splits sum == totalShares");
    }

    function test_RequestRedeem_SplitShares_ThreeChunks() public {
        // 2000 wstETH → 2474 stETH → three chunks of 1000 + 1000 + 474.
        uint256 shares = 2_000 ether;
        uint256 expectedStETH = 2_474 ether;

        vm.prank(address(lidoARM));
        (, uint256 assetsExpected) = wstETHAssetAdapter.requestRedeem(shares);
        assertEq(assetsExpected, expectedStETH, "assetsExpected total");

        assertEq(wstETHAssetAdapter.pendingRequestIdsLength(), 3, "three chunks");

        uint256[3] memory expectedAmounts = [uint256(1_000 ether), uint256(1_000 ether), uint256(474 ether)];

        uint256 sumShares;
        uint256 sumAssets;
        for (uint256 i; i < 3; ++i) {
            uint256 id = wstETHAssetAdapter.pendingRequestId(i);
            assertEq(wstETHAssetAdapter.requestAssets(id), expectedAmounts[i], "chunk asset amount");
            uint256 chunkShares = wstETHAssetAdapter.requestShares(id);
            assertGt(chunkShares, 0, "chunk shares non-zero");
            sumShares += chunkShares;
            sumAssets += wstETHAssetAdapter.requestAssets(id);
        }
        assertEq(sumAssets, expectedStETH, "sum asset amounts == total stETH");
        assertEq(sumShares, shares, "sum share splits == totalShares (remainder absorbed by last chunk)");
    }

    //////////////////////////////////////////////////////
    /// --- redeem — non-1:1 full cycle
    //////////////////////////////////////////////////////
    function test_Redeem_NonOneToOne_FullCycle() public {
        uint256 shares = 100 ether; // 100 wstETH
        uint256 expectedStETH = 123.7 ether;

        vm.startPrank(address(lidoARM));
        wstETHAssetAdapter.requestRedeem(shares);

        uint256 armWethBefore = weth.balanceOf(address(lidoARM));
        (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived) = wstETHAssetAdapter.redeem(shares);
        vm.stopPrank();

        assertEq(sharesClaimed, shares, "sharesClaimed (wstETH)");
        assertEq(assetsExpected, expectedStETH, "assetsExpected (stETH)");
        assertEq(assetsReceived, expectedStETH, "assetsReceived (WETH)");

        // ARM receives WETH equal to the unwrapped stETH amount, NOT the wstETH share count.
        assertEq(weth.balanceOf(address(lidoARM)) - armWethBefore, expectedStETH, "ARM WETH delta");
        assertEq(weth.balanceOf(address(wstETHAssetAdapter)), 0, "adapter WETH post");
        assertEq(address(wstETHAssetAdapter).balance, 0, "adapter ETH post");
    }

    function test_Redeem_NonOneToOne_PartialDrain() public {
        // Multi-chunk request; redeem only the first chunk's shares so we exercise
        // the partial-drain path with non-1:1 share/asset arithmetic.
        uint256 shares = 900 ether;

        vm.startPrank(address(lidoARM));
        wstETHAssetAdapter.requestRedeem(shares);

        uint256 id0 = wstETHAssetAdapter.pendingRequestId(0);
        uint256 id1 = wstETHAssetAdapter.pendingRequestId(1);
        uint256 firstChunkShares = wstETHAssetAdapter.requestShares(id0);
        uint256 firstChunkAssets = wstETHAssetAdapter.requestAssets(id0); // 1000 stETH
        uint256 secondChunkShares = wstETHAssetAdapter.requestShares(id1);

        uint256 armWethBefore = weth.balanceOf(address(lidoARM));
        (uint256 sharesClaimed,, uint256 assetsReceived) = wstETHAssetAdapter.redeem(firstChunkShares);
        vm.stopPrank();

        assertEq(sharesClaimed, firstChunkShares, "sharesClaimed == first chunk shares");
        assertEq(assetsReceived, firstChunkAssets, "assetsReceived == first chunk stETH");
        assertEq(weth.balanceOf(address(lidoARM)) - armWethBefore, firstChunkAssets, "ARM WETH delta");

        // id0 cleared, id1 retained — nextPendingIndex moved forward by exactly one.
        assertEq(wstETHAssetAdapter.requestShares(id0), 0, "id0 cleared");
        assertEq(wstETHAssetAdapter.requestShares(id1), secondChunkShares, "id1 retained");
        assertEq(wstETHAssetAdapter.pendingRequestIdsLength(), 2, "pendingIds length unchanged");
    }
}
