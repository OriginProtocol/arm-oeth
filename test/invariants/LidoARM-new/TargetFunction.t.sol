// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {console} from "forge-std/console.sol";

// Test imports
import {Invariant_LidoARM_Setup_Test} from "./base/Setup.t.sol";

/// @title TargetFunctions
/// @notice TargetFunctions contract for tests, containing the target functions that should be tested.
///         This is the entry point with the contract we are testing. Ideally, it should never revert.
abstract contract TargetFunction is Invariant_LidoARM_Setup_Test {
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                              ✦✦✦ LIDO ARM ✦✦✦                               ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [ ] SwapExactTokensForTokens
    // [ ] SwapTokensForExactTokens
    // [x] Deposit
    // [x] RequestRedeem
    // [x] ClaimRedeem
    // [ ] Allocate
    // [ ] CollectFees
    // [ ] RequestBaseWithdrawal
    // [ ] ClaimBaseWithdrawals
    // --- Admin functions
    // [ ] SetPrices
    // [ ] SetCrossPrice
    // [ ] SetFee
    // [ ] SetActiveMarket
    // [ ] SetARMBuffer
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                                ✦✦✦ LIDO ✦✦✦                                 ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [ ] Rebase
    // [ ] FinalizeWithdrawals
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                            ✦✦✦ ERC4626 MARKETS ✦✦✦                          ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [ ] Deposit
    // [ ] Withdraw
    // [ ] TransferInRewards
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                                   ✦✦✦  ✦✦✦                                   ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝

    ////////////////////////////////////////////////////
    /// --- SWAPS
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    /// --- LIQUIDITY PROVIDERS
    ////////////////////////////////////////////////////
    function targetDeposit(uint128 amount, uint16 from) public {
        (address user, uint256 balance) = selectUserWithLiqudity(from);
        vm.assume(user != address(0)); // Ensure we found a user with liquidity

        // Bound amount
        uint256 boundedAmount = _bound(amount, MINIMUM_DEPOSIT, uint128(balance));
        vm.prank(user);
        lidoARM.deposit(boundedAmount);

        // Log deposit details
        if (consoleLogs) {
            console.log("Deposit: user=%s, amount=%18e", vm.getLabel(user), boundedAmount);
        }
    }

    function targetRequestRedeem(uint128 shares, uint16 from) public {
        (address user, uint256 balance) = selectUserWithShares(from);
        vm.assume(user != address(0)); // Ensure we found a user with shares to redeem

        // Bound shares
        uint256 boundedShares = _bound(shares, MIN_SHARES_TO_REQUEST, uint128(balance));
        vm.prank(user);
        (uint256 requestId,) = lidoARM.requestRedeem(boundedShares);

        // Log redeem request details
        if (consoleLogs) {
            console.log("Request Redeem: user=%s, shares=%18e", vm.getLabel(user), boundedShares);
        }

        _pendingRequestIds.push(requestId); // Track the pending request ID for future claim testing
        shuffle(_pendingRequestIds, from); // Shuffle pending request IDs to ensure randomness in claim
    }

    function targetClaimRedeem(uint128 requestId, uint16 from) public {
        (address user, uint256 requestId, uint256 positionInList) = selectUserWithPendingRequest(from);
        vm.assume(user != address(0)); // Ensure we found a user with a pending redeem request

        vm.prank(user);
        lidoARM.claimRedeem(requestId);

        // Log claim redeem details
        if (consoleLogs) {
            console.log("Claim Redeem: user=%s, requestId=%d", vm.getLabel(user), requestId);
        }

        // Remove the claimed request ID from the pending list
        removeFromList(_pendingRequestIds, positionInList);
        shuffle(_pendingRequestIds, from); // Shuffle pending request IDs to ensure randomness in future claim attempts
    }
    ////////////////////////////////////////////////////
    /// --- LIQUIDITY MANAGMENT
    ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////
    /// --- PRICES AND FEES MANAGEMENT
    ////////////////////////////////////////////////////
}
