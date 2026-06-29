// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_EtherARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @author Origin Protocol Inc
/// @notice Fuzzes LP claim flows across share amounts, post-request yield, post-request loss, and
///         claim warp duration to confirm the request struct, payout math (min of request-time vs
///         claim-time value), and reserved-liquidity release stay consistent.
contract Unit_Fuzz_EtherARM_ClaimRedeem_Test is Unit_EtherARM_Shared_Test {
    using Math for uint256;

    //////////////////////////////////////////////////////
    /// ---                  SETUP                     ---
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();
        desactiveCapManager();
        aliceFirstDeposit(100 ether);
    }

    //////////////////////////////////////////////////////
    /// ---       Fuzz share count, no PnL change      ---
    //////////////////////////////////////////////////////
    function testFuzz_ClaimRedeem_Shares(uint128 fuzzedShares) public {
        uint256 shares = _bound(uint256(fuzzedShares), 1, 100 ether);
        (uint256 requestId, uint256 requestAssets) = aliceRequest(shares);
        // At 1:1 the request locks exactly `shares` assets.
        assertEq(requestAssets, shares, "requestAssets == shares at 1:1");

        skip(CLAIM_DELAY);

        uint256 supplyBefore = etherARM.totalSupply();
        uint256 reservedBefore = etherARM.reservedWithdrawLiquidity();
        uint256 claimedSharesBefore = etherARM.withdrawsClaimedShares();

        // Expect events
        vm.expectEmit({emitter: address(etherARM)});
        emit IERC20.Transfer(address(etherARM), address(0), shares);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(etherARM), alice, requestAssets);
        vm.expectEmit({emitter: address(etherARM)});
        emit AbstractARM.RedeemClaimed(alice, requestId, requestAssets);

        // When
        vm.prank(alice);
        uint256 assets = etherARM.claimRedeem(requestId);

        // Then
        assertEq(assets, requestAssets, "assets returned");
        assertEq(weth.balanceOf(alice), requestAssets, "alice weth");
        assertEq(etherARM.balanceOf(alice), 100 ether - shares, "alice shares");
        assertEq(etherARM.balanceOf(address(etherARM)), 0, "escrow burned");
        assertEq(etherARM.totalSupply(), supplyBefore - shares, "totalSupply");
        assertEq(etherARM.totalAssets(), supplyBefore - shares, "totalAssets matches at 1:1");
        assertEq(etherARM.reservedWithdrawLiquidity(), reservedBefore - requestAssets, "reserved released");
        assertEq(etherARM.withdrawsClaimedShares(), claimedSharesBefore + shares, "withdrawsClaimedShares");

        (, bool claimed,,,) = etherARM.withdrawalRequests(requestId);
        assertTrue(claimed, "request marked claimed");
    }

    //////////////////////////////////////////////////////
    /// ---    Fuzz yield between request and claim    ---
    //////////////////////////////////////////////////////
    function testFuzz_ClaimRedeem_GainAfterRequest(uint128 fuzzedYield) public {
        // Bring in a second LP so the post-claim share price uplift has a holder to land on; without
        // Bobby the only shares left after Alice's claim are the dead-account ones, making the property
        // check less expressive.
        bobbyFirstDeposit(100 ether);

        (uint256 requestId, uint256 requestAssets) = aliceRequest(50 ether);
        assertEq(requestAssets, 50 ether, "requestAssets at 1:1");

        // Lower yield bound at 1 ether so the post-claim share price gain is visible after integer
        // truncation. Upper bound at uint96.max keeps arithmetic well clear of uint128 overflow paths.
        uint256 yield = _bound(uint256(fuzzedYield), 1 ether, type(uint96).max);
        deal(address(weth), address(etherARM), weth.balanceOf(address(etherARM)) + yield);

        skip(CLAIM_DELAY);

        // Sanity: claim-time conversion would value Alice's shares strictly above the request, so the
        // min() at AbstractARM.sol:813-815 selects the request-time value.
        assertGt(etherARM.convertToAssets(50 ether), requestAssets, "claim-time value above request");

        // Expect events
        vm.expectEmit({emitter: address(etherARM)});
        emit IERC20.Transfer(address(etherARM), address(0), 50 ether);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(etherARM), alice, requestAssets);
        vm.expectEmit({emitter: address(etherARM)});
        emit AbstractARM.RedeemClaimed(alice, requestId, requestAssets);

        // When
        vm.prank(alice);
        uint256 assets = etherARM.claimRedeem(requestId);

        // Then
        assertEq(assets, requestAssets, "assets returned = request value");
        assertEq(weth.balanceOf(alice), requestAssets, "alice weth");
        assertEq(etherARM.balanceOf(alice), 50 ether, "alice remaining shares");
        assertEq(etherARM.reservedWithdrawLiquidity(), 0, "reserved released");
        assertEq(etherARM.withdrawsClaimedShares(), 50 ether, "withdrawsClaimedShares");

        // The yield stays with the remaining LPs: share price strictly above 1 after the claim.
        assertGt(etherARM.convertToAssets(1 ether), 1 ether, "share price > 1 after claim");

        (, bool claimed,,,) = etherARM.withdrawalRequests(requestId);
        assertTrue(claimed, "request marked claimed");
    }

    //////////////////////////////////////////////////////
    /// ---     Fuzz loss between request and claim    ---
    //////////////////////////////////////////////////////
    function testFuzz_ClaimRedeem_LossAfterRequest(uint128 fuzzedLoss) public {
        // Alice requests ALL of her shares so the entire pre-loss assets are reserved.
        (uint256 requestId, uint256 requestAssets) = aliceRequest(100 ether);
        assertEq(requestAssets, 100 ether, "requestAssets at 1:1");

        // Bound the loss strictly below the LP-provided assets so the totalAssets() clamp at
        // AbstractARM.sol:901 stays inactive; this keeps the simple mulDiv expectation valid.
        uint256 loss = _bound(uint256(fuzzedLoss), 1, 100 ether - 1);
        vm.prank(address(etherARM));
        weth.transfer(address(0), loss);

        skip(CLAIM_DELAY);

        // Expected payout computed via mulDiv with Floor — algebraically identical to the contract's
        // `shares * totalAssets() / totalSupply()` (no overflow since 100e18 * (1e12 + 100e18) ≪ 2^256).
        // Equality must be exact, no rounding tolerance, so a bug that flips num/denom, uses post-burn
        // supply, or changes rounding direction would diverge here.
        uint256 totalAssetsAfterLoss = MIN_TOTAL_SUPPLY + 100 ether - loss;
        uint256 totalSupplyAtClaim = MIN_TOTAL_SUPPLY + 100 ether;
        uint256 expectedPayout =
            uint256(100 ether).mulDiv(totalAssetsAfterLoss, totalSupplyAtClaim, Math.Rounding.Floor);
        // Property: loss > 0 ⇒ claim-time value strictly below request-time value, so min() selects it.
        assertLt(expectedPayout, requestAssets, "loss should reduce payout below request");
        // Cross-check: the contract's own claim-time conversion matches the test formula.
        assertEq(etherARM.convertToAssets(100 ether), expectedPayout, "convertToAssets matches expected");

        // Expect events (loss path: payout < requestAssets)
        vm.expectEmit({emitter: address(etherARM)});
        emit IERC20.Transfer(address(etherARM), address(0), 100 ether);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(etherARM), alice, expectedPayout);
        vm.expectEmit({emitter: address(etherARM)});
        emit AbstractARM.RedeemClaimed(alice, requestId, expectedPayout);

        // When
        vm.prank(alice);
        uint256 assets = etherARM.claimRedeem(requestId);

        // Then: exact equality — contract and test compute the same floor division.
        assertEq(assets, expectedPayout, "assets returned");
        assertEq(weth.balanceOf(alice), expectedPayout, "alice weth");

        // reservedWithdrawLiquidity is decreased by request.assets (the full reservation), not by the
        // loss-adjusted payout. See AbstractARM.sol:820.
        assertEq(etherARM.reservedWithdrawLiquidity(), 0, "reserved released in full");
        assertEq(etherARM.withdrawsClaimedShares(), 100 ether, "withdrawsClaimedShares");
        assertEq(etherARM.balanceOf(alice), 0, "alice shares");
        assertEq(etherARM.balanceOf(address(etherARM)), 0, "escrow burned");

        (, bool claimed,,,) = etherARM.withdrawalRequests(requestId);
        assertTrue(claimed, "request marked claimed");
    }

    //////////////////////////////////////////////////////
    /// ---           Fuzz claim warp duration         ---
    //////////////////////////////////////////////////////
    function testFuzz_ClaimRedeem_ClaimTimestamp(uint64 fuzzedWarp) public {
        (uint256 requestId, uint256 requestAssets) = aliceRequest(50 ether);

        // Domain restricted to [CLAIM_DELAY, CLAIM_DELAY + 365 days]; we never fuzz into the revert
        // zone (consistent with Swap.fuzz.t.sol's no-revert convention).
        uint256 warp = _bound(uint256(fuzzedWarp), CLAIM_DELAY, CLAIM_DELAY + 365 days);
        skip(warp);

        // Expect events
        vm.expectEmit({emitter: address(etherARM)});
        emit IERC20.Transfer(address(etherARM), address(0), 50 ether);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(etherARM), alice, requestAssets);
        vm.expectEmit({emitter: address(etherARM)});
        emit AbstractARM.RedeemClaimed(alice, requestId, requestAssets);

        // When
        vm.prank(alice);
        uint256 assets = etherARM.claimRedeem(requestId);

        // Then
        assertEq(assets, requestAssets, "assets returned");
        assertEq(weth.balanceOf(alice), requestAssets, "alice weth");
        assertEq(etherARM.reservedWithdrawLiquidity(), 0, "reserved released");
        assertEq(etherARM.withdrawsClaimedShares(), 50 ether, "withdrawsClaimedShares");

        (, bool claimed,,,) = etherARM.withdrawalRequests(requestId);
        assertTrue(claimed, "request marked claimed");
    }
}
