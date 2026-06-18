// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_LidoARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract Unit_LidoARM_ClaimRedeem_Test is Unit_LidoARM_Shared_Test {
    using Math for uint256;

    function setUp() public override {
        super.setUp();
        desactiveCapManager();
        aliceFirstDeposit();
    }

    //////////////////////////////////////////////////////
    /// ---              Happy paths                   ---
    //////////////////////////////////////////////////////
    function test_ClaimRedeem_Default() public {
        aliceRequest(0);
        skip(CLAIM_DELAY);

        // Given
        uint256 expectedAssets = 100 ether;
        uint256 expectedShares = 100 ether;
        assertEq(lidoARM.balanceOf(address(lidoARM)), expectedShares);
        assertEq(lidoARM.totalAssets(), expectedAssets + MIN_TOTAL_SUPPLY);
        assertEq(lidoARM.totalSupply(), expectedShares + MIN_TOTAL_SUPPLY);
        assertEq(lidoARM.reservedWithdrawLiquidity(), expectedAssets);
        assertEq(lidoARM.withdrawsClaimedShares(), 0);

        // Expect
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(lidoARM), address(0), expectedShares);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoARM), alice, expectedAssets);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.RedeemClaimed(alice, 0, expectedAssets);

        // When
        vm.prank(alice);
        lidoARM.claimRedeem(0);

        // Then
        assertEq(weth.balanceOf(alice), expectedAssets, "alice weth");
        assertEq(lidoARM.balanceOf(alice), 0, "alice shares");
        assertEq(lidoARM.balanceOf(address(lidoARM)), 0, "escrow");
        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY, "totalAssets");
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY, "totalSupply");
        assertEq(lidoARM.reservedWithdrawLiquidity(), 0, "reserved");
        assertEq(lidoARM.withdrawsClaimedShares(), expectedShares, "claimed");
    }

    function test_ClaimRedeem_LossAfterRequest() public {
        aliceRequest(0);
        skip(CLAIM_DELAY);

        // Simulate a loss on ARM
        uint256 lossAmount = 20 ether + MIN_TOTAL_SUPPLY / 5; // To ensure we loss 20% of the assets.
        vm.prank(address(lidoARM));
        weth.transfer(address(0), lossAmount); // Burn lossAmount WETH from the ARM balance

        // Given
        uint256 expectedTotalAssets = 100 ether + MIN_TOTAL_SUPPLY - lossAmount;
        uint256 expectedAliceAssets = 80 ether; // Alice should get 80% of her assets back, which is 80 WETH
        uint256 expectedShares = 100 ether; // Shares are not affected by the loss
        assertEq(lidoARM.balanceOf(address(lidoARM)), expectedShares);
        assertEq(lidoARM.totalAssets(), expectedTotalAssets);
        assertEq(lidoARM.totalSupply(), expectedShares + MIN_TOTAL_SUPPLY);
        assertEq(lidoARM.reservedWithdrawLiquidity(), 100 ether);
        assertEq(lidoARM.withdrawsClaimedShares(), 0);

        // Expect
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(lidoARM), address(0), expectedShares);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoARM), alice, expectedAliceAssets);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.RedeemClaimed(alice, 0, expectedAliceAssets);

        // When
        vm.prank(alice);
        lidoARM.claimRedeem(0);

        // Then
        assertEq(weth.balanceOf(alice), expectedAliceAssets, "alice weth");
        assertEq(lidoARM.balanceOf(alice), 0, "alice shares");
        assertEq(lidoARM.balanceOf(address(lidoARM)), 0, "escrow");
        // We have the minimum returned by totalAssets, but in theory it should be 0.8e12.
        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY, "totalAssets");
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY, "totalSupply");
        assertEq(lidoARM.reservedWithdrawLiquidity(), 0, "reserved");
        assertEq(lidoARM.withdrawsClaimedShares(), expectedShares, "claimed");
    }

    function test_ClaimRedeem_LossAfterBothQueued() public {
        // Given: Alice and Bobby both deposited 100 WETH, then both requested redeem of 100 shares.
        bobbyFirstDeposit();
        aliceRequest(0);
        bobbyRequest(0);
        skip(CLAIM_DELAY);

        // Simulate a loss on ARM
        uint256 lossAmount = 40 ether + MIN_TOTAL_SUPPLY / 5; // To ensure we loss 20% of the assets.
        vm.prank(address(lidoARM));
        weth.transfer(address(0), lossAmount); // Burn lossAmount WETH from the ARM balance

        uint256 expectedTotalAssets = 200 ether + MIN_TOTAL_SUPPLY - lossAmount;
        uint256 expectedAliceAssets = 80 ether; // Alice should get 80% of her assets back, which is 80 WETH
        uint256 expectedBobbyAssets = 80 ether; // Bobby should also get 80% of his assets back, which is 80 WETH
        uint256 expectedShares = 100 ether; // Shares are not affected by the loss
        assertEq(lidoARM.balanceOf(address(lidoARM)), expectedShares * 2);
        assertEq(lidoARM.totalAssets(), expectedTotalAssets);
        assertEq(lidoARM.totalSupply(), expectedShares * 2 + MIN_TOTAL_SUPPLY);
        assertEq(lidoARM.reservedWithdrawLiquidity(), 200 ether);
        assertEq(lidoARM.withdrawsClaimedShares(), 0);

        // When Alice claims
        vm.prank(alice);
        lidoARM.claimRedeem(0);

        // When Bobby claims
        vm.prank(bobby);
        lidoARM.claimRedeem(1);

        // Then
        assertEq(weth.balanceOf(alice), expectedAliceAssets, "alice weth");
        assertEq(weth.balanceOf(bobby), expectedBobbyAssets, "bobby weth");
        assertEq(lidoARM.balanceOf(alice), 0, "alice shares");
        assertEq(lidoARM.balanceOf(bobby), 0, "bobby shares");
        assertEq(lidoARM.balanceOf(address(lidoARM)), 0, "escrow");
        // We have the minimum returned by totalAssets, but in theory it should be 0.8e12.
        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY, "totalAssets");
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY, "totalSupply");
        assertEq(lidoARM.reservedWithdrawLiquidity(), 0, "reserved");
        assertEq(lidoARM.withdrawsClaimedShares(), expectedShares * 2, "claimed");
    }

    function test_ClaimRedeem_LossBeforeBothRequests() public {
        // ARM loss 20%
        // Alice Request + Claim 50% of her shares
        // Then Bobby Request + Claim  25% of his sharesafter Alice claimed
        // They should have both the same loss of 20% even if Bobby claim after Alice and
        // the ARM is already 20% less valuable when Bobby claim, because the loss is shared
        // equally at the time of the claim based on the shares that are being redeemed.

        // Given: Alice already deposited 100 WETH in setUp. Bobby also deposits 100 WETH.
        bobbyFirstDeposit();

        // Simulate a 20% loss on the ARM: burn 20% of the total assets.
        uint256 lossAmount = 40 ether + MIN_TOTAL_SUPPLY / 5; // 20% of (200 ether + MIN_TOTAL_SUPPLY)
        vm.prank(address(lidoARM));
        weth.transfer(address(0), lossAmount);

        // Sanity: share price is now exactly 0.8.
        assertEq(lidoARM.totalAssets(), 160 ether + 4 * MIN_TOTAL_SUPPLY / 5, "totalAssets after loss");
        assertEq(lidoARM.totalSupply(), 200 ether + MIN_TOTAL_SUPPLY, "totalSupply after loss");
        assertEq(lidoARM.convertToAssets(1 ether), 0.8 ether, "share price after loss");

        // When: Alice requests redeem of 50% of her shares (50 shares).
        uint256 aliceShares = 50 ether;
        uint256 expectedAliceAssets = 40 ether; // 50 * 0.8
        (uint256 aliceRequestId, uint256 aliceAssetsAtRequest) = aliceRequest(aliceShares);
        assertEq(aliceAssetsAtRequest, expectedAliceAssets, "alice assets at request");

        skip(CLAIM_DELAY);

        // Alice claims.
        vm.prank(alice);
        lidoARM.claimRedeem(aliceRequestId);

        // Then: Alice received 80% of her 50-share value = 40 WETH (20% loss).
        assertEq(weth.balanceOf(alice), expectedAliceAssets, "alice weth after claim");
        assertEq(lidoARM.balanceOf(alice), 50 ether, "alice remaining shares");

        // After Alice's claim, totalAssets / totalSupply should still give 0.8 per share.
        assertEq(lidoARM.totalAssets(), 120 ether + 4 * MIN_TOTAL_SUPPLY / 5, "totalAssets after alice claim");
        assertEq(lidoARM.totalSupply(), 150 ether + MIN_TOTAL_SUPPLY, "totalSupply after alice claim");
        assertEq(lidoARM.convertToAssets(1 ether), 0.8 ether, "share price after alice claim");

        // When: Bobby requests redeem of 25% of his shares (25 shares), AFTER Alice claimed.
        uint256 bobbyShares = 25 ether;
        uint256 expectedBobbyAssets = 20 ether; // 25 * 0.8
        (uint256 bobbyRequestId, uint256 bobbyAssetsAtRequest) = bobbyRequest(bobbyShares);
        assertEq(bobbyAssetsAtRequest, expectedBobbyAssets, "bobby assets at request");

        skip(CLAIM_DELAY);

        // Bobby claims.
        vm.prank(bobby);
        lidoARM.claimRedeem(bobbyRequestId);

        // Then: Bobby received 80% of his 25-share value = 20 WETH (20% loss), the SAME loss as Alice
        // even though he redeemed a different amount and after Alice claimed.
        assertEq(weth.balanceOf(bobby), expectedBobbyAssets, "bobby weth after claim");
        assertEq(lidoARM.balanceOf(bobby), 75 ether, "bobby remaining shares");

        // Loss equality check: both lost exactly 20% on the shares they redeemed.
        uint256 aliceLossBps = (aliceShares - expectedAliceAssets) * 10_000 / aliceShares;
        uint256 bobbyLossBps = (bobbyShares - expectedBobbyAssets) * 10_000 / bobbyShares;
        assertEq(aliceLossBps, 2_000, "alice loss = 20%");
        assertEq(bobbyLossBps, 2_000, "bobby loss = 20%");
        assertEq(aliceLossBps, bobbyLossBps, "alice and bobby share the loss equally");
    }

    function test_ClaimRedeem_RecoveryBetweenClaims() public {
        // Alice Request 50% of her shares at the pre-loss price (1.0)
        // Then ARM loss 20% (between Alice request and Alice claim)
        // Alice Claim -> the min(request.assets, assetsAtClaim) clause caps her payout at the loss-adjusted value
        // Then ARM recover some funds, so it is now only a 10% loss
        // Then Bobby Request + Claim 25% of his shares after Alice claimed
        // They shouldn't have the same loss.

        // Given: Alice already deposited 100 WETH in setUp. Bobby also deposits 100 WETH.
        bobbyFirstDeposit();

        // Alice requests 50% of her shares (50) BEFORE the loss, at share price 1.0.
        uint256 aliceShares = 50 ether;
        uint256 expectedAliceAssets = 40 ether; // 50 * 0.8, alice still ends up with a 20% loss via the claim-time min
        (uint256 aliceRequestId, uint256 aliceAssetsAtRequest) = aliceRequest(aliceShares);
        assertEq(aliceAssetsAtRequest, 50 ether, "alice request.assets locked at pre-loss price");
        assertEq(lidoARM.reservedWithdrawLiquidity(), 50 ether, "reserved at pre-loss price");

        // Now simulate a 20% loss on the ARM, AFTER Alice's request but BEFORE her claim.
        uint256 lossAmount = 40 ether + MIN_TOTAL_SUPPLY / 5; // 20% of (200 ether + MIN_TOTAL_SUPPLY)
        vm.prank(address(lidoARM));
        weth.transfer(address(0), lossAmount);

        // Sanity: share price is now 0.8 (20% loss). totalSupply is unchanged: Alice's shares were
        // escrowed (not burnt) by requestRedeem, so they still share the loss pro-rata.
        assertEq(lidoARM.totalAssets(), 160 ether + 4 * MIN_TOTAL_SUPPLY / 5, "totalAssets after loss");
        assertEq(lidoARM.totalSupply(), 200 ether + MIN_TOTAL_SUPPLY, "totalSupply after loss");
        assertEq(lidoARM.convertToAssets(1 ether), 0.8 ether, "share price after loss");

        // Alice claims. The min() clause caps her payout: request.assets (50) > assetsAtClaim (40)
        // so she only receives 40 WETH, locking in the same 20% loss as if she'd requested post-loss.
        skip(CLAIM_DELAY);
        vm.prank(alice);
        lidoARM.claimRedeem(aliceRequestId);
        assertEq(weth.balanceOf(alice), expectedAliceAssets, "alice weth after claim");

        // After Alice's claim: 120 ether + 4 * MIN_TOTAL_SUPPLY / 5 / 150 ether + MIN_TOTAL_SUPPLY -> share price still 0.8.
        assertEq(lidoARM.totalAssets(), 120 ether + 4 * MIN_TOTAL_SUPPLY / 5, "totalAssets after alice claim");
        assertEq(lidoARM.totalSupply(), 150 ether + MIN_TOTAL_SUPPLY, "totalSupply after alice claim");
        assertEq(lidoARM.convertToAssets(1 ether), 0.8 ether, "share price after alice claim");

        // ARM recovers some funds: top up WETH so the share price becomes 0.9 (only a 10% loss).
        // Target: assets = 0.9 * (150 ether + MIN_TOTAL_SUPPLY) = 135 ether + 9 * MIN_TOTAL_SUPPLY / 10. Delta = 15 ether + MIN_TOTAL_SUPPLY / 10.
        uint256 recoveryAmount = 15 ether + MIN_TOTAL_SUPPLY / 10;
        deal(address(weth), address(lidoARM), weth.balanceOf(address(lidoARM)) + recoveryAmount);
        assertEq(lidoARM.totalAssets(), 135 ether + 9 * MIN_TOTAL_SUPPLY / 10, "totalAssets after recovery");
        assertEq(lidoARM.convertToAssets(1 ether), 0.9 ether, "share price after recovery");

        // Bobby requests 25% of his shares at the recovered price (0.9).
        uint256 bobbyShares = 25 ether;
        uint256 expectedBobbyAssets = 22.5 ether; // 25 * 0.9, only a 10% loss
        (uint256 bobbyRequestId, uint256 bobbyAssetsAtRequest) = bobbyRequest(bobbyShares);
        assertEq(bobbyAssetsAtRequest, expectedBobbyAssets, "bobby assets at request");

        skip(CLAIM_DELAY);
        vm.prank(bobby);
        lidoARM.claimRedeem(bobbyRequestId);
        assertEq(weth.balanceOf(bobby), expectedBobbyAssets, "bobby weth after claim");
        assertEq(lidoARM.balanceOf(bobby), 75 ether, "bobby remaining shares");

        // Loss comparison: Alice locked in 20% but Bobby only suffers 10%.
        // The loss is "locked in" at the time of the claim, so the early exiter (Alice)
        // does not benefit from the later recovery.
        uint256 aliceLossBps = (aliceShares - expectedAliceAssets) * 10_000 / aliceShares;
        uint256 bobbyLossBps = (bobbyShares - expectedBobbyAssets) * 10_000 / bobbyShares;
        assertEq(aliceLossBps, 2_000, "alice loss = 20%");
        assertEq(bobbyLossBps, 1_000, "bobby loss = 10%");
        assertTrue(aliceLossBps != bobbyLossBps, "alice and bobby do NOT share the loss equally");
    }

    function test_ClaimRedeem_GainAfterRequest() public {
        // Alice requests at price 1.0. Yield arrives. Alice should still only get request.assets
        // (the cap), and the forfeited upside should accrue to the remaining LPs (Bob + dust).

        bobbyFirstDeposit();

        uint256 aliceShares = 50 ether;
        (uint256 aliceId, uint256 aliceAssetsAtRequest) = aliceRequest(aliceShares);
        assertEq(aliceAssetsAtRequest, 50 ether, "request.assets at price 1.0");

        // Yield: 20 WETH donated to the ARM. Share price rises from 1.0 to 1.1.
        uint256 yield = 20 ether;
        deal(address(weth), address(lidoARM), weth.balanceOf(address(lidoARM)) + yield);
        assertEq(lidoARM.totalAssets(), 220 ether + MIN_TOTAL_SUPPLY, "totalAssets with yield");
        assertEq(lidoARM.totalSupply(), 200 ether + MIN_TOTAL_SUPPLY, "totalSupply unchanged");

        skip(CLAIM_DELAY);

        // Without the cap, Alice would receive convertToAssets(50) ~ 55 ether.
        // The cap clamps her to request.assets = 50 ether exactly.
        vm.prank(alice);
        uint256 aliceClaimed = lidoARM.claimRedeem(aliceId);
        assertEq(aliceClaimed, 50 ether, "alice receives request.assets (capped)");
        assertEq(weth.balanceOf(alice), 50 ether, "alice weth balance");

        // After Alice's claim, the ~5 ether of upside she gave up stays in the pool. Bob's 100
        // shares should now be worth strictly more than 100 ether.
        uint256 bobShareValue = lidoARM.previewRedeem(100 ether);
        uint256 expectedBobShareValue =
            Math.mulDiv(100 ether, 170 ether + MIN_TOTAL_SUPPLY, 150 ether + MIN_TOTAL_SUPPLY);
        assertEq(bobShareValue, expectedBobShareValue, "bob's share value reflects forfeited upside");
        assertGt(bobShareValue, 100 ether, "bob gained from alice's forfeited upside");
    }

    function test_ClaimRedeem_TwoLossesSeparatedByClaim() public {
        // First loss happens. Alice claims, locking in the first loss only.
        // Then a second loss happens. Bob (who waited) eats both losses, compounding.

        bobbyFirstDeposit();

        // Loss #1: -20% on (200 ether + MIN_TOTAL_SUPPLY)
        uint256 loss1 = 40 ether + MIN_TOTAL_SUPPLY / 5;
        vm.prank(address(lidoARM));
        weth.transfer(address(0xdead), loss1);
        assertEq(lidoARM.convertToAssets(1 ether), 0.8 ether, "price after loss #1");

        // Alice requests 50 of her 100 shares and claims at price 0.8.
        uint256 aliceShares = 50 ether;
        (uint256 aliceId,) = aliceRequest(aliceShares);
        skip(CLAIM_DELAY);
        vm.prank(alice);
        uint256 aliceClaimed = lidoARM.claimRedeem(aliceId);
        assertEq(aliceClaimed, 40 ether, "alice locks in 20% loss");

        // Share price is still 0.8 after Alice's burn (loss already absorbed pro-rata).
        assertEq(lidoARM.convertToAssets(1 ether), 0.8 ether, "price still 0.8 after alice claim");
        assertEq(lidoARM.totalAssets(), 120 ether + 4 * MIN_TOTAL_SUPPLY / 5, "totalAssets after alice claim");
        assertEq(lidoARM.totalSupply(), 150 ether + MIN_TOTAL_SUPPLY, "totalSupply after alice claim");

        // Loss #2: -20% of CURRENT totalAssets (120 ether + 4 * MIN_TOTAL_SUPPLY / 5).
        uint256 loss2 = 24 ether + 4 * MIN_TOTAL_SUPPLY / 25;
        vm.prank(address(lidoARM));
        weth.transfer(address(0xdead), loss2);
        assertEq(lidoARM.totalAssets(), 96 ether + 16 * MIN_TOTAL_SUPPLY / 25, "totalAssets after loss #2");
        // New price: 0.8 * 0.8 = 0.64
        assertEq(lidoARM.convertToAssets(1 ether), 0.64 ether, "price after loss #2");

        // Bob requests 25 shares at the new price and claims.
        uint256 bobShares = 25 ether;
        (uint256 bobId, uint256 bobAssetsAtRequest) = bobbyRequest(bobShares);
        assertEq(bobAssetsAtRequest, 16 ether, "bob's request.assets at price 0.64");
        skip(CLAIM_DELAY);
        vm.prank(bobby);
        uint256 bobClaimed = lidoARM.claimRedeem(bobId);
        assertEq(bobClaimed, 16 ether, "bob claims at price 0.64");

        // Loss comparison: Alice 20%, Bob 36% (= 1 - 0.8*0.8).
        uint256 aliceLossBps = (aliceShares - aliceClaimed).mulDiv(10_000, aliceShares);
        uint256 bobLossBps = (bobShares - bobClaimed).mulDiv(10_000, bobShares);
        assertEq(aliceLossBps, 2_000, "alice loss = 20%");
        assertEq(bobLossBps, 3_600, "bob loss = 36% (compound)");
    }

    function test_ClaimRedeem_WithActiveMarket() public {
        // Configure the active market, push Alice's WETH to it, then claim. The claim must
        // pull the missing liquidity back from the market in the same transaction.

        address[] memory markets = new address[](1);
        markets[0] = address(mockERC4626Market);
        vm.prank(governor);
        lidoARM.addMarkets(markets);
        vm.prank(governor);
        lidoARM.setActiveMarket(address(mockERC4626Market));

        // Move Alice's already-deposited 100 WETH to the market (armBuffer = 0).
        lidoARM.allocate();
        assertEq(weth.balanceOf(address(lidoARM)), 0, "ARM drained to market");
        assertGt(mockERC4626Market.balanceOf(address(lidoARM)), 0, "ARM holds market shares");

        // Alice requests her 100 shares and waits.
        (uint256 aliceId,) = aliceRequest(0);
        skip(CLAIM_DELAY);

        // Claim must withdraw 100 ether from the market and forward to Alice.
        vm.prank(alice);
        uint256 aliceClaimed = lidoARM.claimRedeem(aliceId);

        assertEq(aliceClaimed, 100 ether, "claim payout");
        assertEq(weth.balanceOf(alice), 100 ether, "alice received WETH from market path");
        assertEq(weth.balanceOf(address(lidoARM)), 0, "ARM left with no WETH");
    }

    function test_ClaimRedeem_ByOperator() public {
        // Alice requests; operator (not Alice) calls claimRedeem. WETH still goes to Alice.
        (uint256 aliceId,) = aliceRequest(0);
        skip(CLAIM_DELAY);

        vm.prank(operator);
        lidoARM.claimRedeem(aliceId);

        assertEq(weth.balanceOf(alice), 100 ether, "alice received WETH");
        assertEq(weth.balanceOf(operator), 0, "operator did NOT pocket the WETH");
    }

    function test_ClaimRedeem_AtExactClaimTimestamp() public {
        (uint256 aliceId,) = aliceRequest(0);
        // Exactly at the claimTimestamp -> require uses `<=`, must succeed.
        skip(CLAIM_DELAY);
        vm.prank(alice);
        lidoARM.claimRedeem(aliceId);
        assertEq(weth.balanceOf(alice), 100 ether, "claim at the exact timestamp boundary");
    }

    function test_ClaimRedeem_FullReservationReleasedOnLoss() public {
        // Alice locks request.assets = 100 ether at price 1.0. Then a 20% loss happens.
        // Her payout is 80, but reservedWithdrawLiquidity must be reduced by 100 (the full
        // request-time reservation), and the unreserved 20 ether becomes value for remaining LPs.

        bobbyFirstDeposit();
        (uint256 aliceId,) = aliceRequest(0); // 100 shares -> request.assets = 100
        assertEq(lidoARM.reservedWithdrawLiquidity(), 100 ether, "reservation at request time");

        // 20% loss on (200 ether + MIN_TOTAL_SUPPLY)
        uint256 lossAmount = 40 ether + MIN_TOTAL_SUPPLY / 5;
        vm.prank(address(lidoARM));
        weth.transfer(address(0xdead), lossAmount);

        skip(CLAIM_DELAY);
        vm.prank(alice);
        uint256 aliceClaimed = lidoARM.claimRedeem(aliceId);

        // Payout is loss-adjusted (80), but reservation released is the full 100.
        assertEq(aliceClaimed, 80 ether, "alice payout = 80");
        assertEq(lidoARM.reservedWithdrawLiquidity(), 0, "full reservation released");

        // The 20 ether delta (reservation - payout) stays in the pool, raising the value
        // backing Bob's 100 remaining shares. Bob now backs (160 + 4 * MIN_TOTAL_SUPPLY / 5) - 80 = 80 + 4 * MIN_TOTAL_SUPPLY / 5
        // against 200 + MIN_TOTAL_SUPPLY - 100 = 100 + MIN_TOTAL_SUPPLY supply -> price still 0.8 per share.
        assertEq(weth.balanceOf(address(lidoARM)), 80 ether + 4 * MIN_TOTAL_SUPPLY / 5, "balance after claim");
        assertEq(lidoARM.totalSupply(), 100 ether + MIN_TOTAL_SUPPLY, "supply after burn");
        assertEq(lidoARM.convertToAssets(1 ether), 0.8 ether, "price still 0.8 for remaining LPs");
    }

    //////////////////////////////////////////////////////
    /// ---                  REVERTS                   ---
    //////////////////////////////////////////////////////
    function test_ClaimRedeem_RevertWhen_InsufficientLiquidity() public {
        // Goal: Alice and Bob both have a queued request, but the ARM holds only 50 WETH liquid
        // (the rest replaced by stETH valued 1:1). The FIFO gate must block BOTH claims since
        // claimable() in shares < either request.queued.

        bobbyFirstDeposit();
        addBaseAsset(steth); // Configure stETH so it counts in totalAssets at the cross price

        // Both request 100% of their shares at price 1.0 -> each request.assets = 100 ether
        (uint256 aliceId,) = aliceRequest(0);
        (uint256 bobId,) = bobbyRequest(0);
        assertEq(lidoARM.reservedWithdrawLiquidity(), 200 ether, "reserved = 200");

        // Swap 150 WETH out, 150 stETH in: balance(WETH) drops to 50, totalAssets stays at 200
        // (so the share price stays 1.0 and the gate cannot scale up via convertToShares).
        vm.prank(address(lidoARM));
        weth.transfer(address(0xdead), 150 ether);
        deal(address(steth), address(lidoARM), 150 ether);

        // Sanity: state is "balance-poor, totalAssets-rich"
        assertEq(weth.balanceOf(address(lidoARM)), 50 ether + MIN_TOTAL_SUPPLY, "balance WETH = 50");
        assertEq(lidoARM.totalAssets(), 200 ether + MIN_TOTAL_SUPPLY, "totalAssets unchanged");
        assertEq(lidoARM.totalSupply(), 200 ether + MIN_TOTAL_SUPPLY, "totalSupply unchanged");

        skip(CLAIM_DELAY);

        // claimable() in shares = convertToShares(50 ether + MIN_TOTAL_SUPPLY) ~= 50 ether + MIN_TOTAL_SUPPLY
        // Alice queued = 100 ether (in shares) -> cannot claim
        // Bob queued = 200 ether -> cannot claim either
        vm.prank(alice);
        vm.expectRevert(AbstractARM.QueuePendingLiquidity.selector);
        lidoARM.claimRedeem(aliceId);

        vm.prank(bobby);
        vm.expectRevert(AbstractARM.QueuePendingLiquidity.selector);
        lidoARM.claimRedeem(bobId);
    }

    function test_ClaimRedeem_RevertWhen_NotRequesterOrOperator() public {
        (uint256 aliceId,) = aliceRequest(0);
        skip(CLAIM_DELAY);

        vm.prank(bobby);
        vm.expectRevert(AbstractARM.NotRequesterOrOperator.selector);
        lidoARM.claimRedeem(aliceId);
    }

    function test_ClaimRedeem_RevertWhen_BeforeClaimDelay() public {
        (uint256 aliceId,) = aliceRequest(0);
        // One second short of the delay -> still locked.
        skip(CLAIM_DELAY - 1);
        vm.prank(alice);
        vm.expectRevert(AbstractARM.ClaimDelayNotMet.selector);
        lidoARM.claimRedeem(aliceId);
    }

    function test_ClaimRedeem_RevertWhen_AlreadyClaimed() public {
        (uint256 aliceId,) = aliceRequest(0);
        skip(CLAIM_DELAY);
        vm.prank(alice);
        lidoARM.claimRedeem(aliceId);

        // Re-claim attempt
        vm.prank(alice);
        vm.expectRevert(AbstractARM.AlreadyClaimed.selector);
        lidoARM.claimRedeem(aliceId);
    }

    function test_ClaimRedeem_RevertWhen_Paused() public {
        (uint256 aliceId,) = aliceRequest(0);
        skip(CLAIM_DELAY);

        vm.prank(governor);
        lidoARM.pause();

        vm.prank(alice);
        vm.expectRevert(AbstractARM.ContractPaused.selector);
        lidoARM.claimRedeem(aliceId);
    }
}
