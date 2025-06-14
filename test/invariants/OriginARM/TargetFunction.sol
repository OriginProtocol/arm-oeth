// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {MockVault} from "test/unit/mocks/MockVault.sol";
import {Properties} from "test/invariants/OriginARM/Properties.sol";
import {MathComparisons} from "test/invariants/OriginARM/MathComparisons.sol";

// OpenZeppelin imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// Forge imports
import {console} from "forge-std/console.sol";

abstract contract TargetFunction is Properties {
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                           ✦✦✦ PUBLIC FUNCTIONS ✦✦✦                           ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] Deposit
    // [x] RequestRedeem
    // [x] ClaimRedeem
    // [x] SwapExactTokensForTokens
    // [x] SwapTokensForExactTokens
    // [x] Allocate
    // [x] ClaimOriginWithdrawals

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                       ✦✦✦ PERMISSIONNED FUNCTIONS ✦✦✦                        ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] SetPrices
    // [x] SetCrossPrice
    // [x] SetFee
    // [x] CollectFees
    // [x] SetActiveMarket
    // [x] SetARMBuffer
    // [x] RequestOriginWithdrawal

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                    ✦✦✦ REPLICATED BEHAVIOUR FUNCTIONS ✦✦✦                    ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] SimulateEarnOnMarket
    // [ ] SimulateLossOnMarket     (not sure)
    // [x] Donation to the ARM

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                  ✦✦✦ NON-VIEW FUNCTION NOT IMPLEMENTED ✦✦✦                   ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    //  ⛒  SetCapManager
    //  ⛒  SetFeeCollector
    //  ⛒  AddMarket
    //  ⛒  RemoveMarket

    using Math for uint256;
    using SafeCast for uint256;
    using MathComparisons for uint256;

    function handler_deposit(uint8 seed, uint88 amount) public {
        // Get a random user from the list of lps
        address user = getRandomLPs(seed);

        // Console log data
        if (CONSOLE_LOG) console.log("deposit() \t\t From: %s | \t Amount: %s", name(user), faa(amount));

        // Expected amount of shares
        uint256 previewDeposit = originARM.previewDeposit(amount);

        // Main call
        vm.prank(user);
        uint256 shares = originARM.deposit(amount);

        require(shares == previewDeposit, "Deposit: Expected != received");
        sum_ws_deposit += amount;
    }

    function handler_requestRedeem(uint8 seed, uint96 shares) public {
        // Get a random user from the list of lps with a balance
        address user = getRandomLPs(seed, true);
        // Ensure a user is selected, otherwise skip
        vm.assume(user != address(0));

        // Bound shares to the balance of the user
        shares = uint96(_bound(shares, 0, originARM.balanceOf(user)));

        uint256 expectedId = originARM.nextWithdrawalIndex();
        uint256 expectedAmount = originARM.previewRedeem(shares);
        // Console log data
        if (CONSOLE_LOG) {
            console.log("requestRedeem() \t From: %s | \t Shares: %s | \t ID: %s", name(user), faa(shares), expectedId);
        }

        // Main call
        vm.prank(user);
        (uint256 id, uint256 amount) = originARM.requestRedeem(shares);
        requests[user].push(id);

        require(id == expectedId, "Expected ID != received");
        require(amount == expectedAmount, "Expected amount != received");
        sum_ws_redeem += amount;
    }

    function handler_claimRedeem(uint8 seed, uint16 seed_id) public {
        // Get a random user from the list of lps with a request
        (address user, uint256 id, uint256 expectedAmount, uint40 ts) = getRandomLPsWithRequest(seed, seed_id);
        // Ensure a user is selected, otherwise skip
        vm.assume(user != address(0));

        // Console log data
        if (CONSOLE_LOG) {
            console.log("claimRedeem() \t From: %s | \t Amount: %s | \t ID: %s", name(user), faa(expectedAmount), id);
        }

        // Timejump to the claim delay
        if (ts > block.timestamp) vm.warp(ts);

        // Main call
        vm.prank(user);
        originARM.claimRedeem(id);

        // Remove the request from the list
        removeRequest(user, id);
        sum_ws_user_claimed += expectedAmount;
    }

    function handler_setARMBuffer(uint64 pct) public {
        pct = uint64(_bound(pct, 0, 10)) * 1e17;

        // Console log data
        if (CONSOLE_LOG) console.log("setARMBuffer() \t From: %s | \t Percen: %16e %", "Owner", pct);

        // Main call
        vm.prank(governor);
        originARM.setARMBuffer(pct);
    }

    function handler_setActiveMarket(uint8 seed) public {
        // Get a random market from the list of markets
        (address fromM, address toM) = getRandomMarket(seed);
        vm.assume(fromM != address(0) || toM != address(0));

        // Console log data
        if (CONSOLE_LOG) {
            console.log("setActiveMarket() \t From: %s | \t Market: %s -> %s", "Owner", nameM(fromM), nameM(toM));
        }

        // Main call
        vm.prank(governor);
        originARM.setActiveMarket(toM);
    }

    function handler_allocate() public {
        address market = originARM.activeMarket();
        vm.assume(market != address(0));

        int256 delta = getLiquidityDelta();
        if (delta > 0) {
            // As SiloMarket doesn't have previewDeposit function, we check it directly on the underlying market.
            if (market == address(siloMarket)) market = address(market2);

            // Small edge case where due to donation, minted shares could be 0 which makes the call revert.
            vm.assume(IERC4626(market).previewDeposit(uint256(delta)) > 0);
        }
        // Console log data
        if (CONSOLE_LOG) console.log("allocate() \t\t From: %s", "Owner");

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
        if (CONSOLE_LOG) {
            console.log(
                "setPrices() \t\t From: Owner | \t Buy   : %s | \t Sell: %s",
                faa(buyPrice / 1e18),
                faa(sellPrice / 1e18)
            );
        }

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
        uint256 lowerBound = Math.max(priceScale - maxCrossPriceDeviation, buyPrice + 1);

        vm.assume(upperBound >= lowerBound);

        newCrossPrice = uint120(_bound(newCrossPrice, lowerBound, upperBound));

        if (originARM.crossPrice() > newCrossPrice) vm.assume(os.balanceOf(address(originARM)) <= MIN_TOTAL_SUPPLY);

        // Console log data
        if (CONSOLE_LOG) console.log("setCrossPrice() \t From: %s | \t CrossP: %s", "Owner", faa(newCrossPrice / 1e18));

        // Main call
        vm.prank(governor);
        originARM.setCrossPrice(newCrossPrice);
    }

    function handler_swapExactTokensForTokens(uint8 seed, bool OSForWS, uint88 amountIn) public {
        // token0 is ws and token1 is os
        address[] memory path = new address[](2);
        path[0] = OSForWS ? address(os) : address(ws);
        path[1] = OSForWS ? address(ws) : address(os);
        // Get a random user with a balance
        (address user, uint256 balance) = getRandomSwapperWithBalance(seed, 0, IERC20(path[0]));
        // Ensure a user is selected, otherwise skip
        vm.assume(user != address(0));

        uint256 price = path[0] == address(ws) ? originARM.traderate0() : originARM.traderate1();
        uint256 liquidityAvailable = getLiquidityAvailable(path[1]);

        // We reverse the price calculation to get the amountIn based on the amountOut
        uint256 maxAmountInWithAmountOut = liquidityAvailable * PRICE_SCALE / price;
        // Bound the amountIn to the balance of the user and the max amountIn
        amountIn = uint88(_bound(amountIn, 0, Math.min(balance, maxAmountInWithAmountOut)));
        vm.assume(amountIn > 0);

        // Console log data
        if (CONSOLE_LOG) {
            console.log(
                "swapExactTokensFor() \t From: %s | \t Amount: %s | \t Direction: %s",
                name(user),
                faa(amountIn),
                OSForWS ? "OS -> WS" : "WS -> OS"
            );
        }

        // Main call
        vm.prank(user);
        uint256[] memory outputs = originARM.swapExactTokensForTokens(amountIn, 0, path, user, block.timestamp + 1);

        // Ensure amountIn and amountOut are correct
        require(outputs[0] == amountIn, "AmountIn: Expected != sent");
        require(outputs[1] == amountIn * price / PRICE_SCALE, "AmountOut: Expected != received");
        OSForWS
            ? (sum_os_swapIn += outputs[0], sum_ws_swapOut += outputs[1])
            : (sum_ws_swapIn += outputs[0], sum_os_swapOut += outputs[1]);
    }

    function handler_swapTokensForExactTokens(uint8 seed, bool OSForWS, uint88 amountOut) public {
        // token0 is ws and token1 is os
        address[] memory path = new address[](2);
        path[0] = OSForWS ? address(os) : address(ws);
        path[1] = OSForWS ? address(ws) : address(os);
        // Get a random user with a balance
        (address user, uint256 balance) = getRandomSwapperWithBalance(seed, 0, IERC20(path[0]));
        // Ensure a user is selected, otherwise skip
        vm.assume(user != address(0) && balance >= 3);

        uint256 price = path[0] == address(ws) ? originARM.traderate0() : originARM.traderate1();
        uint256 liquidityAvailable = getLiquidityAvailable(path[1]);

        // Get the maximum of amountIn based on the maximum of amountOut
        uint256 maxAmountOutWithAmountIn = ((balance - 3) * price) / PRICE_SCALE;
        // Bound the amountOut to the available liquidity in ARM and maxAmountOut based on user balance
        amountOut = uint88(_bound(amountOut, 0, Math.min(liquidityAvailable, maxAmountOutWithAmountIn)));
        vm.assume(amountOut > 0);

        uint256 expectedAmountIn = ((amountOut * PRICE_SCALE) / price) + 3;
        // Console log data
        if (CONSOLE_LOG) {
            console.log(
                "swapTokensForExact() \t From: %s | \t Amount: %s | \t Direction: %s",
                name(user),
                faa(expectedAmountIn),
                OSForWS ? "OS -> WS" : "WS -> OS"
            );
        }

        uint256[] memory outputs = new uint256[](2);
        // Main call
        vm.prank(user);
        outputs = originARM.swapTokensForExactTokens(amountOut, type(uint96).max, path, user, block.timestamp + 1);

        // Ensure amountIn used is correct
        require(outputs[0] == expectedAmountIn, "Expected != sent");
        require(outputs[1] == amountOut, "Expected != received");
        OSForWS
            ? (sum_os_swapIn += outputs[0], sum_ws_swapOut += outputs[1])
            : (sum_ws_swapIn += outputs[0], sum_os_swapOut += outputs[1]);
    }

    function handler_collectFees() public {
        // Ensure there is enough liquidity to claim fees
        uint256 feesAccrued = originARM.feesAccrued();
        vm.assume(feesAccrued <= getLiquidityAvailable(address(ws)));

        // Console log data
        if (CONSOLE_LOG) console.log("collectFees() \t From: Owner | \t Amount: %s ", faa(feesAccrued));

        // Main call
        vm.prank(governor);
        uint256 fees = originARM.collectFees();

        sum_feesCollected += fees;
    }

    function handler_setFee(uint16 feePct) public {
        // Ensure there is enough liquidity to claim fees
        uint256 feesAccrued = originARM.feesAccrued();
        vm.assume(feesAccrued <= getLiquidityAvailable(address(ws)));

        feePct = uint16(_bound(feePct, 0, 50)) * 100; // 0% - 50%

        if (CONSOLE_LOG) console.log("setFee() \t\t From: Owner | \t Percen: %2e %", feePct);

        vm.prank(governor);
        originARM.setFee(feePct);

        sum_feesCollected += feesAccrued;
    }

    function handler_requestOriginWithdrawal(uint128 amount) public {
        // Only request amount based on amount held by the ARM.
        amount = uint128(_bound(amount, 0, os.balanceOf(address(originARM))));
        uint256 expectedId = MockVault(address(vault)).requestCount() + 1;
        vm.assume(amount > 0);

        // Console log data
        if (CONSOLE_LOG) {
            console.log("requestOWithdraw() \t From: Owner | \t Amount: %s | \t ID: %s", faa(amount), expectedId);
        }

        // Main call
        vm.prank(governor);
        originARM.requestOriginWithdrawal(amount);

        // Add requestId to the list
        originRequests.push(expectedId);

        sum_os_redeem += amount;
    }

    function handler_claimOriginWithdrawals(uint16 requestCount, uint256 seed) public {
        vm.assume(originRequests.length > 0);
        requestCount = uint16(_bound(requestCount, 1, originRequests.length));

        // This will remove the requestId from the list
        uint256[] memory ids = getRandomOriginRequest(requestCount, seed);

        // Console log data
        if (CONSOLE_LOG) console.log("claimOWithdrawals() \t From: Owner | \t IDs: ", uintArrayToString(ids));

        // Main call
        vm.prank(governor);
        uint256 totalClaimed = originARM.claimOriginWithdrawals(ids);

        sum_ws_arm_claimed += totalClaimed;
    }

    function handler_donateToARM(uint88 amount, bool OSOrWs, uint8 seed) public {
        //We do this to avoid calling this function too often
        vm.assume(seed % 20 == 0 && DONATE);
        amount = uint88(_bound(amount, 1, type(uint88).max));

        // Console log data
        if (CONSOLE_LOG) {
            console.log(
                "donateToARM() \t From: DONAT | \t Amount: %s | \t Token: %s", faa(amount), OSOrWs ? "OS" : "WS"
            );
        }

        address donator = makeAddr("donator");
        deal(OSOrWs ? address(os) : address(ws), donator, amount);

        // Mail call
        vm.prank(address(donator));
        (OSOrWs ? os : ws).transfer(address(originARM), amount);

        OSOrWs ? sum_os_donated += amount : sum_ws_donated += amount;
    }

    function handler_simulateMarketActivity(uint8 seed, bool depositOrEarn, uint80 amount) public {
        // A user will deposit token in the market
        address market = getRandom(markets, seed);
        require(market != address(0), "Market should not be 0");

        // Handle when the market is the SiloMarketAdapter
        if (market == address(siloMarket)) market = address(market2);
        vm.assume(IERC4626(market).previewDeposit(amount) > 0);

        if (depositOrEarn) {
            deal(address(ws), address(this), amount);
            // Console log data
            if (CONSOLE_LOG) {
                console.log(
                    "depositOnMarket() \t From: Owner | \t Amount: %s | \t Market: %s", faa(amount), nameM(market)
                );
            }

            ws.approve(market, type(uint80).max);
            IERC4626(market).deposit(amount, address(this));
        } else {
            uint256 marketBalance = ws.balanceOf(market);
            uint256 pct = uint256(_bound(seed, 1, 10)) * 1e16; // 1% - 10%
            amount = uint80(marketBalance * pct / 1e18);
            deal(address(ws), address(this), amount);

            // Console log data
            if (CONSOLE_LOG) {
                console.log("earnOnMarket() \t From: Owner | \t Amount: %s | \t Market: %s", faa(amount), nameM(market));
            }
            ws.transfer(market, amount);
        }
    }

    function handler_afterInvariants() public {
        // - Claim all the dust available in the lending market by cheating
        // Eventhough this is not the expected behaviour of the contract, we need to
        // ensure that the contract is not holding any funds in the lending market
        // at the end of the test, to ensure that shares are up only.
        vm.prank(address(originARM));
        for (uint256 i; i < markets.length; i++) {
            address market = markets[i];
            if (market != address(0)) {
                uint256 shares = IERC4626(markets[i]).balanceOf(address(originARM));
                if (shares > 0) {
                    vm.prank(address(originARM));
                    IERC4626(markets[i]).redeem(shares, address(originARM), address(originARM));
                }
            }
        }

        // - Finalize claim all the Origin requests
        if (originRequests.length > 0) {
            vm.prank(governor);
            originARM.claimOriginWithdrawals(originRequests);
        }

        // - Remove the active market to pull out all deposited funds
        address activeMarket = originARM.activeMarket();
        if (activeMarket != address(0)) {
            vm.prank(governor);
            originARM.setActiveMarket(address(0));
        }

        // - Set the prices to 1:1
        vm.prank(governor);
        originARM.setPrices(0, PRICE_SCALE);

        // - Swap all the OS on ARM to WS
        deal(address(ws), makeAddr("swapper"), type(uint120).max);
        vm.startPrank(makeAddr("swapper"));
        ws.approve(address(originARM), type(uint120).max);
        originARM.swapTokensForExactTokens(ws, os, os.balanceOf(address(originARM)), type(uint256).max, address(this));
        vm.stopPrank();

        // - All user request redeem with the remaining shares
        for (uint256 i = 0; i < lps.length; i++) {
            address user = lps[i];
            uint256 shares = originARM.balanceOf(user);
            if (shares > 0) {
                vm.prank(user);
                (uint256 id_,) = originARM.requestRedeem(shares);
                requests[user].push(id_);
            }
        }

        // - Finalize all users claim request
        skip(CLAIM_DELAY);
        for (uint256 i = 0; i < lps.length; i++) {
            address user = lps[i];
            uint256[] memory ids = requests[user];
            if (ids.length > 0) {
                vm.startPrank(user);
                for (uint256 j = 0; j < ids.length; j++) {
                    originARM.claimRedeem(ids[j]);
                }
                vm.stopPrank();
            }
        }

        // - Claim fees
        originARM.collectFees();

        address dead = address(0xdEaD);
        vm.startPrank(dead);
        (uint256 id,) = originARM.requestRedeem(originARM.balanceOf(dead));
        skip(CLAIM_DELAY);
        originARM.claimRedeem(id);
        vm.stopPrank();

        // - Ensure everything is empty
        // No more OS in the ARM
        require(os.balanceOf(address(originARM)) == 0, "ARM should be OS empty");
        require(ws.balanceOf(address(originARM)) == 0, "ARM should be WS empty");
        // No unclaimed requests
        uint256 len = originARM.nextWithdrawalIndex();
        for (uint256 i; i < len; i++) {
            (, bool claimed,,,) = originARM.withdrawalRequests(i);
            require(claimed, "All withdrawals should be claimed");
        }
        // No users with shares
        len = lps.length;
        for (uint256 i; i < len; i++) {
            require(originARM.balanceOf(lps[i]) == 0, "User should have no shares anymore");
        }
    }

    function getLiquidityAvailable(address token) public view returns (uint256) {
        if (token == address(os)) {
            return os.balanceOf(address(originARM));
        } else if (token == address(ws)) {
            uint256 withdrawsQueued = originARM.withdrawsQueued();
            uint256 withdrawsClaimed = originARM.withdrawsClaimed();
            uint256 outstandingWithdrawals = withdrawsQueued - withdrawsClaimed;
            uint256 balance = ws.balanceOf(address(originARM));
            if (outstandingWithdrawals > balance) return 0;

            return ws.balanceOf(address(originARM)) - outstandingWithdrawals;
        }
        return 0;
    }

    function getLiquidityDelta() public view returns (int256) {
        (uint256 availableAssets, uint256 outstandingWithdrawals) = getAvailableAssets();
        if (availableAssets == 0) return 0;

        int256 armLiquidity =
            SafeCast.toInt256(ws.balanceOf(address(originARM))) - SafeCast.toInt256(outstandingWithdrawals);
        uint256 armBuffer = originARM.armBuffer();
        uint256 targetArmLiquidity = availableAssets * armBuffer / 1e18;

        return armLiquidity - SafeCast.toInt256(targetArmLiquidity);
    }

    function getAvailableAssets() public view returns (uint256 availableAssets, uint256 outstandingWithdrawals) {
        uint256 liquidityAsset = ws.balanceOf(address(originARM));
        uint256 baseAsset = os.balanceOf(address(originARM));
        uint256 crossPrice = originARM.crossPrice();
        uint256 externalWithdrawQueue = originARM.vaultWithdrawalAmount();
        uint256 assets = liquidityAsset + externalWithdrawQueue + (baseAsset * crossPrice / PRICE_SCALE);

        address activeMarket = originARM.activeMarket();
        if (activeMarket != address(0)) {
            assets += IERC4626(activeMarket).previewRedeem(IERC4626(activeMarket).balanceOf(address(originARM)));
        }

        outstandingWithdrawals = originARM.withdrawsQueued() - originARM.withdrawsClaimed();
        if (assets < outstandingWithdrawals) return (0, outstandingWithdrawals);

        availableAssets = assets - outstandingWithdrawals;
    }

    function assertLpsAreUpOnly(uint256 tolerance) public view {
        for (uint256 i; i < lps.length; i++) {
            require(
                ws.balanceOf(lps[i]).gteApproxRel(INITIAL_AMOUNT_LPS, tolerance),
                "User should not have less than initial amount"
            );
        }
    }
}
