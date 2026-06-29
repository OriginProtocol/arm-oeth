// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_Lido_Shared_Test} from "../shared/Shared.t.sol";

// Contracts
import {AbstractLidoAssetAdapter} from "contracts/adapters/AbstractLidoAssetAdapter.sol";

// Libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Test-only adapter that exposes `_splitAmounts` and `_splitShares` as
///         external functions, and lets `_assetsToShares` be driven by a stored
///         rate. The rate is interpreted as `_assetsToShares(x) = x * rate / 1e18`,
///         so `rate == 1e18` is 1:1, `rate < 1e18` makes shares smaller than assets
///         (rate-up scenario), and `rate > 1e18` makes them larger.
contract ExposedLidoAdapter is AbstractLidoAssetAdapter {
    uint256 public mockRate;

    constructor(address _arm, address _weth, address _steth, address _queue)
        AbstractLidoAssetAdapter(_arm, _weth, _steth, _queue)
    {}

    function setMockRate(uint256 v) external {
        mockRate = v;
    }

    function exposed_splitAmounts(uint256 amount) external pure returns (uint256[] memory) {
        return _splitAmounts(amount);
    }

    function exposed_splitShares(uint256 totalShares, uint256[] memory amounts, uint256 totalAssets)
        external
        view
        returns (uint256[] memory)
    {
        return _splitShares(totalShares, amounts, totalAssets);
    }

    function MAX_AMOUNT() external pure returns (uint256) {
        return MAX_WITHDRAWAL_AMOUNT;
    }

    // Required by IAssetAdapter; unused by these fuzz tests.
    function convertToAssets(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function convertToShares(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function _pullSharesAndConvertToSteth(address, uint256) internal pure override returns (uint256) {
        return 0;
    }

    function _assetsToShares(uint256 assets) internal view override returns (uint256) {
        return Math.mulDiv(assets, mockRate, 1e18, Math.Rounding.Floor);
    }
}

/// @notice Property-based fuzz tests for the two pure-ish chunking helpers in
///         `AbstractLidoAssetAdapter`: `_splitAmounts` and `_splitShares`. Both
///         functions feed `requestRedeem` and their invariants are essential to
///         the ARM's withdrawal accounting (queue chunks sum to the request,
///         share splits sum to the user's redeem amount).
contract Unit_Fuzz_LidoARM_Split_Test is Unit_Lido_Shared_Test {
    ExposedLidoAdapter internal exposed;
    uint256 internal MAX;

    function setUp() public override {
        super.setUp();
        // Deploy directly (not via proxy); the constructor sets the stETH approval on this contract's
        // own storage, which is all `_splitAmounts` / `_splitShares` need.
        exposed = new ExposedLidoAdapter({
            _arm: address(this), _weth: address(weth), _steth: address(steth), _queue: address(lidoWithdrawalQueue)
        });
        MAX = exposed.MAX_AMOUNT();
    }

    //////////////////////////////////////////////////////
    /// --- _splitAmounts
    //////////////////////////////////////////////////////

    /// @notice Invariants over `_splitAmounts(amount)`:
    ///         1. chunk count == ceil(amount / MAX)
    ///         2. sum(chunks) == amount (exact, no loss)
    ///         3. every non-final chunk equals MAX
    ///         4. final chunk is in (0, MAX]
    function testFuzz_SplitAmounts_Invariants(uint256 amount) public view {
        // Cap at ~100 chunks (100_000 ether). The chunking arithmetic is invariant in the chunk count,
        // so 100 chunks is enough to exercise the loop while keeping memory allocation well within
        // EVM limits.
        amount = _bound(amount, 1, 100 * MAX);

        uint256[] memory chunks = exposed.exposed_splitAmounts(amount);

        // Property 1: chunk count
        uint256 expectedCount = (amount + MAX - 1) / MAX;
        assertEq(chunks.length, expectedCount, "chunk count == ceil(amount / MAX)");

        // Property 2 + 3 + 4 in a single pass
        uint256 sum;
        uint256 lastIdx = chunks.length - 1;
        for (uint256 i; i < chunks.length; ++i) {
            if (i < lastIdx) {
                assertEq(chunks[i], MAX, "non-final chunk == MAX");
            } else {
                assertGt(chunks[i], 0, "final chunk > 0");
                assertLe(chunks[i], MAX, "final chunk <= MAX");
            }
            sum += chunks[i];
        }
        assertEq(sum, amount, "sum(chunks) == amount");
    }

    /// @notice Boundary cases — amounts at and around MAX_WITHDRAWAL_AMOUNT.
    function testFuzz_SplitAmounts_AroundBoundary(uint256 offset) public view {
        // Probe amount = MAX +/- offset to stress the boundary between 1-chunk and 2-chunk splits.
        offset = _bound(offset, 0, MAX - 1);

        // amount = MAX - offset (clamped to >= 1): always exactly 1 chunk
        {
            uint256 amount = MAX - offset;
            if (amount == 0) amount = 1;
            uint256[] memory chunks = exposed.exposed_splitAmounts(amount);
            assertEq(chunks.length, 1, "(MAX - offset) -> 1 chunk");
            assertEq(chunks[0], amount, "(MAX - offset) -> chunk == amount");
        }

        // amount = MAX + offset: 1 chunk when offset == 0, otherwise 2 chunks of MAX + offset
        {
            uint256 amount = MAX + offset;
            uint256[] memory chunks = exposed.exposed_splitAmounts(amount);
            if (offset == 0) {
                assertEq(chunks.length, 1, "MAX -> 1 chunk");
                assertEq(chunks[0], MAX, "MAX -> chunk == MAX");
            } else {
                assertEq(chunks.length, 2, "(MAX + offset) -> 2 chunks");
                assertEq(chunks[0], MAX, "first chunk == MAX");
                assertEq(chunks[1], offset, "second chunk == offset");
            }
        }
    }

    //////////////////////////////////////////////////////
    /// --- _splitShares
    //////////////////////////////////////////////////////

    /// @notice Invariants over `_splitShares(totalShares, amounts, totalAssets)`:
    ///         1. shareSplits.length == amounts.length
    ///         2. sum(shareSplits) == totalShares (last chunk absorbs all rounding)
    ///         3. each non-final shareSplit <= cumulative remainingShares at that step
    ///         The function is exercised across a wide range of share/asset ratios
    ///         (mockRate) so all three branches inside the loop are explored:
    ///            - happy path (splitShares <= remainingShares, splitShares > 0)
    ///            - cap branch (splitShares > remainingShares)
    ///            - zero-fallback branch (splitShares == 0)
    function testFuzz_SplitShares_Invariants(uint256 totalAssets, uint256 totalShares, uint256 rate) public {
        // Multi-chunk regime (>= 2 chunks) up to ~100 chunks. The loop logic is invariant in chunk
        // count beyond this; 100 chunks is enough to exercise branches without OOG on array allocation.
        totalAssets = _bound(totalAssets, MAX + 1, 100 * MAX);
        // totalShares is decoupled from totalAssets on purpose: extreme imbalances drive the cap and
        // zero-fallback branches inside the loop.
        totalShares = _bound(totalShares, 1, type(uint96).max);
        // Rate spans 6 orders of magnitude below 1:1 to 6 orders above, covering both the cap branch
        // (rate big enough that one chunk's worth of shares overshoots remainingShares) and the zero
        // branch (rate small enough that floor(MAX * rate / 1e18) rounds to zero).
        rate = _bound(rate, 1, 1e24);

        exposed.setMockRate(rate);
        uint256[] memory amounts = exposed.exposed_splitAmounts(totalAssets);
        uint256[] memory splits = exposed.exposed_splitShares(totalShares, amounts, totalAssets);

        // Property 1: length matches amounts
        assertEq(splits.length, amounts.length, "length matches amounts");

        // Property 2: sum equals totalShares
        // Property 3: no non-final split exceeds the shares that were still available before it
        uint256 sum;
        uint256 remaining = totalShares;
        uint256 lastIdx = splits.length - 1;
        for (uint256 i; i < splits.length; ++i) {
            if (i < lastIdx) {
                // The non-final cap ensures splits[i] never exceeds what was available going in.
                assertLe(splits[i], remaining, "split <= remaining at iteration");
            }
            sum += splits[i];
            // remaining cannot underflow because of the assertion above
            remaining -= splits[i];
        }
        assertEq(sum, totalShares, "sum(splits) == totalShares");
        assertEq(remaining, 0, "remaining drained to zero");
    }

    /// @notice With a consistent rate (totalShares ~= totalAssets * rate / 1e18) the function should
    ///         produce splits that mirror the asset proportions to within the last-chunk remainder.
    ///         This is the "real world" path — wstETH-style — and it must never enter the cap branch
    ///         on non-final chunks under self-consistent math.
    function testFuzz_SplitShares_ConsistentRate(uint256 totalAssets, uint256 rate) public {
        totalAssets = _bound(totalAssets, MAX + 1, 100 * MAX);
        // Restrict rate so 1 asset is worth at least 1e-3 share and at most 1e3 shares; outside this
        // range the consistency property below collapses because `_assetsToShares(MAX)` underflows to
        // zero or `totalShares` overflows the assertion bounds.
        rate = _bound(rate, 1e15, 1e21);

        exposed.setMockRate(rate);
        uint256 totalShares = Math.mulDiv(totalAssets, rate, 1e18, Math.Rounding.Floor);
        // Skip degenerate runs where rounding wipes out totalShares (rate near 1e15 with small assets).
        vm.assume(totalShares > 0);

        uint256[] memory amounts = exposed.exposed_splitAmounts(totalAssets);
        uint256[] memory splits = exposed.exposed_splitShares(totalShares, amounts, totalAssets);

        // Per-chunk lower bound: the natural conversion of the chunk's assets.
        uint256 expectedPerFullChunk = Math.mulDiv(MAX, rate, 1e18, Math.Rounding.Floor);

        uint256 sum;
        uint256 lastIdx = splits.length - 1;
        for (uint256 i; i < splits.length; ++i) {
            if (i < lastIdx) {
                // Non-final splits equal _assetsToShares(MAX) under self-consistent inputs, because
                // the cap and zero-fallback branches don't fire when totalShares matches totalAssets.
                assertEq(splits[i], expectedPerFullChunk, "non-final split == _assetsToShares(MAX)");
            }
            sum += splits[i];
        }
        assertEq(sum, totalShares, "sum(splits) == totalShares");
    }
}
