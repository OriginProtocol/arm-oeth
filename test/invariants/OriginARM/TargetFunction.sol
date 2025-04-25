// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Properties} from "test/invariants/OriginARM/Properties.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {console} from "forge-std/console.sol";

abstract contract TargetFunction is Properties {
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                           ✦✦✦ PUBLIC FUNCTIONS ✦✦✦                           ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] Deposit
    // [x] RequestRedeem
    // [x] ClaimRedeem
    // [ ] SwapExactTokensForTokens
    // [ ] SwapTokensForExactTokens
    // [x] Allocate
    // [ ] ClaimOriginWithdrawals

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                       ✦✦✦ PERMISSIONNED FUNCTIONS ✦✦✦                        ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] SetPrices
    // [x] SetCrossPrice
    // [ ] SetFee
    // [ ] CollectFees
    // [x] SetActiveMarket
    // [x] SetARMBuffer
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

    using Math for uint256;

    function handler_deposit(uint8 seed, uint80 amount) public {
        // Get a random user from the list of lps
        address user = getRandomLPs(seed);

        // Console log data
        console.log("deposit() \t\t From: %s | \t Amount: %s", name(user), faa(amount));

        // Main call
        vm.prank(user);
        originARM.deposit(amount);
    }

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

    function handler_claimRedeem(uint8 seed, uint16 seed_id) public {
        // Get a random user from the list of lps with a request
        (address user, uint256 id, uint256 expectedAmount, uint40 ts) = getRandomLPsWithRequest(seed, seed_id);
        // Ensure a user is selected, otherwise skip
        vm.assume(user != address(0));

        // Console log data
        console.log("claimRedeem() \t From: %s | \t Amount: %s | \t ID: %s", name(user), faa(expectedAmount), id);

        // Timejump to the claim delay
        vm.warp(ts);
        // Main call
        vm.prank(user);
        originARM.claimRedeem(id);

        // Remove the request from the list
        removeRequest(user, id);
    }

    function handler_setARMBuffer(uint64 pct) public {
        pct = uint64(_bound(pct, 0, 10)) * 1e17;

        // Console log data
        console.log("setARMBuffer() \t From: %s | \t Percen: %16e %", "Owner", pct);

        // Main call
        vm.prank(governor);
        originARM.setARMBuffer(pct);
    }

    function handler_setActiveMarket(uint8 seed) public {
        // Get a random market from the list of markets
        (address fromM, address toM) = getRandomMarket(seed);
        vm.assume(fromM != address(0) || toM != address(0));

        // Console log data
        console.log("setActiveMarket() \t From: %s | \t Market: %s -> %s", "Owner", nameM(fromM), nameM(toM));

        // Main call
        vm.prank(governor);
        originARM.setActiveMarket(toM);
    }

    function handler_allocate() public {
        vm.assume(originARM.activeMarket() != address(0));
        // Console log data
        console.log("allocate() \t\t From: %s", "Owner");

        // Main call
        vm.prank(governor);
        originARM.allocate();
    }

    function handler_setPrices(uint256 buyPrice, uint256 sellPrice) public {
        // On the current LidoARM, we can see that sell price almost never changes and is always 0.9999 * 1e36.
        // The buy price is the one that changes more often, but it is always between 0.9990 * 1e36 and 0.9999 * 1e36.
        // We will try to mimic this behaviour for buyPrice, while trying to reach sometimes price with small decimals.
        // We will try to have most of the variation close from the first decimals like 0.999043 and reduces the one
        // around the last decimals, like 0.950000000000000000_000000000000000023.
        uint256 crossPrice = originARM.crossPrice();
        buyPrice = uint256(_bound(buyPrice, MIN_BUY_PRICE / 1e30, (crossPrice - 1) / 1e30)) * 1e30 - buyPrice % 1e30;
        sellPrice = _bound(sellPrice, crossPrice, MAX_SELL_PRICE);

        // Console log data
        console.log(
            "setPrices() \t\t From: Owner | \t Buy   : %s | \t Sell: %s", faa(buyPrice / 1e18), faa(sellPrice / 1e18)
        );

        // Main call
        vm.prank(governor);
        originARM.setPrices(buyPrice, sellPrice);
    }

    function handler_setCrossPrice(uint120 newCrossPrice) public {
        uint256 priceScale = 1e36;
        uint256 maxCrossPriceDeviation = 20e32;
        uint256 buyPrice = originARM.traderate1();
        uint256 sellPrice = (priceScale ** 2) / originARM.traderate0();

        // Conditions:
        // 1.a. crossPrice >= priceScale - maxCrossPriceDeviation
        // 1.b. crossPrice > buyPrice
        // 2.a. crossPrice <= priceScale
        // 2.b. crossPrice <= sellPrice
        uint256 upperBound = Math.min(priceScale, sellPrice);
        uint256 lowerBound = Math.max(priceScale - maxCrossPriceDeviation, buyPrice);

        vm.assume(upperBound >= lowerBound);

        newCrossPrice = uint120(_bound(newCrossPrice, lowerBound, upperBound));

        if (originARM.crossPrice() > newCrossPrice) vm.assume(os.balanceOf(address(originARM)) >= MIN_TOTAL_SUPPLY);

        // Console log data
        console.log("setCrossPrice() \t From: %s | \t CrossP: %s", "Owner", faa(newCrossPrice / 1e18));

        // Main call
        vm.prank(governor);
        originARM.setCrossPrice(newCrossPrice);
    }
}
