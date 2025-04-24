// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Properties} from "test/invariants/OriginARM/Properties.sol";

import {console} from "forge-std/console.sol";

abstract contract TargetFunction is Properties {
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                           ✦✦✦ PUBLIC FUNCTIONS ✦✦✦                           ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] Deposit
    // [x] RequestRedeem
    // [ ] ClaimRedeem
    // [ ] SwapExactTokensForTokens
    // [ ] SwapTokensForExactTokens
    // [ ] Allocate
    // [ ] ClaimOriginWithdrawals

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                       ✦✦✦ PERMISSIONNED FUNCTIONS ✦✦✦                        ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [ ] SetPrices
    // [ ] SetCrossPrice
    // [ ] SetFee
    // [ ] CollectFees
    // [ ] SetActiveMarket
    // [ ] SetARMBuffer
    // [ ] RequestOriginWithdrawal

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                    ✦✦✦ REPLICATED BEHAVIOUR FUNCTIONS ✦✦✦                    ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [ ] SimulateEarnOnMarket
    // [ ] SimulateLossOnMarket     (not sure)
    // [ ] Donation to the ARM

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                  ✦✦✦ NON-VIEW FUNCTION NOT IMPLEMENTED ✦✦✦                   ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [ ] SetCapManager
    // [ ] SetFeeCollector
    // [ ] AddMarket
    // [ ] RemoveMarket

    function handler_deposit(uint8 seed, uint80 amount) public {
        // Get a random user from the list of lps
        address user = getRandomLPs(seed);

        // Console log data
        console.log("deposit() \t\t From: %s | \t Amount: %s", name(user), faa(amount));

        // Main call
        vm.prank(user);
        originARM.deposit(amount);
    }

    mapping(address => uint256[]) public requests;

    function handler_requestRedeem(uint8 seed, uint96 amount) public {
        // Get a random user from the list of lps with a balance
        address user = getRandomLPs(seed, true);
        // Ensure a user is selected, otherwise skip
        vm.assume(user != address(0));

        // Bound amount to the balance of the user
        amount = uint96(_bound(amount, 0, originARM.balanceOf(user)));

        uint256 expectedId = originARM.nextWithdrawalIndex();
        // Console log data
        console.log("requestRedeem() \t From: %s | \t Amount: %s | \t ID: %s", name(user), faa(amount), expectedId);

        // Main call
        vm.prank(user);
        (uint256 id,) = originARM.requestRedeem(amount);
        requests[user].push(id);
    }
}
