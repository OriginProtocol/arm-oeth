// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_LidoARM_Shared_Test} from "../../Shared.t.sol";

// Contracts
import {AbstractLidoAssetAdapter} from "contracts/adapters/AbstractLidoAssetAdapter.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

/// @notice Test-only concrete adapter that exposes injectable values for the
///         abstract's two virtual hooks. Lets `_splitShares` be driven through
///         its two defensive branches:
///         - `splitShares > remainingShares` (cap to remaining)
///         - `splitShares == 0`               (proportional fallback)
///         Neither branch is reachable through `StETHAssetAdapter` (1:1) or
///         `WstETHAssetAdapter` (rate ≥ 1) under self-consistent unwrap math.
contract TestableLidoAdapter is AbstractLidoAssetAdapter {
    uint256 public mockAssetsOut; // value returned by _pullSharesAndConvertToSteth
    uint256 public mockAssetsToSharesRate; // _assetsToShares(x) = x * rate / 1e18
    bool public mockReturnZero; // if true, _assetsToShares unconditionally returns 0

    constructor(address _arm, address _weth, address _steth, address _queue)
        AbstractLidoAssetAdapter(_arm, _weth, _steth, _queue)
    {}

    function setMockAssetsOut(uint256 v) external {
        mockAssetsOut = v;
    }

    function setMockAssetsToSharesRate(uint256 v) external {
        mockAssetsToSharesRate = v;
    }

    function setMockReturnZero(bool v) external {
        mockReturnZero = v;
    }

    // Required by IAssetAdapter; unused by the tests in this file.
    function convertToAssets(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function convertToShares(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function _pullSharesAndConvertToSteth(
        address owner,
        uint256 /*shares*/
    )
        internal
        override
        returns (uint256 assetsOut)
    {
        assetsOut = mockAssetsOut;
        IERC20(address(steth)).transferFrom(owner, address(this), assetsOut);
    }

    function _assetsToShares(uint256 assets) internal view override returns (uint256) {
        if (mockReturnZero) return 0;
        return assets * mockAssetsToSharesRate / 1e18;
    }
}

/// @notice Targeted branch coverage for `AbstractLidoAssetAdapter._splitShares`.
///         The two defensive branches inside the loop are unreachable from the
///         shipped concrete adapters under consistent math, so we drive them
///         through a `TestableLidoAdapter` that injects arbitrary values for
///         `_pullSharesAndConvertToSteth` and `_assetsToShares`.
contract Unit_LidoARM_AbstractLidoAssetAdapter_Test is Unit_LidoARM_Shared_Test {
    TestableLidoAdapter internal testableAdapter;

    function setUp() public override {
        super.setUp();

        // Use the test contract itself as the simulated ARM. No prank needed: msg.sender
        // during direct calls into the adapter is already `address(this)`.
        testableAdapter = new TestableLidoAdapter({
            _arm: address(this), _weth: address(weth), _steth: address(steth), _queue: address(lidoWithdrawalQueue)
        });

        // Seed stETH at the simulated ARM and approve the adapter to pull it.
        deal(address(steth), address(this), 10_000 ether);
        steth.approve(address(testableAdapter), type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- _splitShares branch coverage
    //////////////////////////////////////////////////////

    /// @notice Hits `if (splitShares > remainingShares) splitShares = remainingShares;`
    ///         on a non-final chunk while keeping the capped value > 0 (so the
    ///         zero-fallback branch is not entered).
    ///         Setup: assetsOut = 2500e18 → 3 chunks of 1000/1000/500. With rate
    ///         1.0, `_assetsToShares(1000e18) = 1000e18`. Passing only 1500e18
    ///         totalShares means at i=1 we have remainingShares=500e18 but the
    ///         computed splitShares=1000e18 — overshooting and triggering the cap.
    function test_SplitShares_CapsWhenSplitExceedsRemaining() public {
        testableAdapter.setMockAssetsOut(2_500 ether);
        testableAdapter.setMockAssetsToSharesRate(1e18);

        uint256 totalShares = 1_500 ether;

        testableAdapter.requestRedeem(totalShares);

        assertEq(testableAdapter.pendingRequestIdsLength(), 3, "chunks");
        uint256 id0 = testableAdapter.pendingRequestId(0);
        uint256 id1 = testableAdapter.pendingRequestId(1);
        uint256 id2 = testableAdapter.pendingRequestId(2);

        // i=0: splitShares=1000e18 ≤ remainingShares=1500e18 → no cap. shareSplits[0]=1000e18.
        assertEq(testableAdapter.requestShares(id0), 1_000 ether, "chunk0 not capped");
        // i=1: splitShares=1000e18 > remainingShares=500e18 → cap to 500e18.
        assertEq(testableAdapter.requestShares(id1), 500 ether, "chunk1 capped to remainingShares");
        // i=2 (last): absorbs the (zero) remainder.
        assertEq(testableAdapter.requestShares(id2), 0, "chunk2 absorbs zero remainder");

        // Invariant: sum equals totalShares.
        uint256 sum = testableAdapter.requestShares(id0) + testableAdapter.requestShares(id1)
            + testableAdapter.requestShares(id2);
        assertEq(sum, totalShares, "sum == totalShares");
    }

    /// @notice Hits `if (splitShares == 0) splitShares = remainingShares * amounts[i] / remainingAssets;`
    ///         on a non-final chunk. Drive it by forcing `_assetsToShares` to
    ///         return zero — the fallback then assigns a proportional split.
    ///         Setup: assetsOut = 2500e18 → 3 chunks of 1000/1000/500.
    ///         totalShares = 500e18. With mockReturnZero, every non-final
    ///         iteration enters the fallback branch.
    function test_SplitShares_FallbackWhenSplitIsZero() public {
        testableAdapter.setMockAssetsOut(2_500 ether);
        testableAdapter.setMockReturnZero(true);

        uint256 totalShares = 500 ether;

        testableAdapter.requestRedeem(totalShares);

        assertEq(testableAdapter.pendingRequestIdsLength(), 3, "chunks");
        uint256 id0 = testableAdapter.pendingRequestId(0);
        uint256 id1 = testableAdapter.pendingRequestId(1);
        uint256 id2 = testableAdapter.pendingRequestId(2);

        // i=0: splitShares = 0 → fallback = remainingShares(500) * amounts[0](1000) / remainingAssets(2500) = 200.
        assertEq(testableAdapter.requestShares(id0), 200 ether, "chunk0 fallback");
        // i=1: remainingShares=300, remainingAssets=1500. fallback = 300 * 1000 / 1500 = 200.
        assertEq(testableAdapter.requestShares(id1), 200 ether, "chunk1 fallback");
        // i=2 (last): shareSplits[2] = remainingShares = 100.
        assertEq(testableAdapter.requestShares(id2), 100 ether, "chunk2 takes remainder");

        // Invariant: sum equals totalShares.
        uint256 sum = testableAdapter.requestShares(id0) + testableAdapter.requestShares(id1)
            + testableAdapter.requestShares(id2);
        assertEq(sum, totalShares, "sum == totalShares");
    }
}
