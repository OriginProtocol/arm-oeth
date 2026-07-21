// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {console} from "forge-std/console.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MockMorpho} from "./mocks/MockMorpho.sol";

// Interfaces
import {IERC20, IAssetAdapter} from "contracts/Interfaces.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

// Test imports
import {Invariant_LidoARM_Setup_Test} from "./base/Setup.t.sol";

/// @title TargetFunctions
/// @notice TargetFunctions contract for tests, containing the target functions that should be tested.
///         This is the entry point with the contract we are testing. Ideally, it should never revert.
abstract contract TargetFunction is Invariant_LidoARM_Setup_Test {
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                              ✦✦✦ LIDO ARM ✦✦✦                               ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] SwapExactTokensForTokens
    // [x] SwapTokensForExactTokens
    // [x] Deposit
    // [x] RequestRedeem
    // [x] ClaimRedeem
    // [x] Allocate
    // [x] CollectFees
    // [x] RequestBaseWithdrawal
    // [x] ClaimBaseWithdrawals
    // --- Admin functions
    // [x] SetPrices
    // [x] SetCrossPrice
    // [x] SetFee
    // [x] SetActiveMarket
    // [x] SetARMBuffer
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                                ✦✦✦ LIDO ✦✦✦                                 ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] Rebase
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                            ✦✦✦ ERC4626 MARKETS ✦✦✦                          ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] Deposit
    // [x] Withdraw
    // [x] TransferInRewards
    // [x] SetUtilizationRate
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                                   ✦✦✦  ✦✦✦                                   ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝

    ////////////////////////////////////////////////////
    /// --- SWAPS
    ////////////////////////////////////////////////////
    function targetSwapExactTokensForTokens(uint88 amount, bool stETHOrWstETH, bool buyOrSell)
        public
        ensureSharePriceNotDecreased
    {
        address baseAsset = stETHOrWstETH ? address(steth) : address(wsteth);
        // buyOrSell: true = ARM buys base asset (trader sends base, gets WETH)
        //            false = ARM sells base asset (trader sends WETH, gets base)
        address tokenIn = buyOrSell ? baseAsset : address(weth);
        address tokenOut = buyOrSell ? address(weth) : baseAsset;

        (uint128 buyPrice, uint128 sellPrice, uint128 buyLiqRemaining, uint128 sellLiqRemaining,,,,,) =
            lidoARM.baseAssetConfigs(baseAsset);

        // 1. Max output the ARM can deliver
        uint256 maxAmountOut;
        if (buyOrSell) {
            // ARM pays WETH: min(unreserved WETH, buyLiquidityRemaining)
            // Note: _ensureLiquidityAvailableForSwap checks amountOut + reserved <= balance,
            // so even a 0 swap reverts when reserved > balance. Use active market too.
            uint256 bal = weth.balanceOf(address(lidoARM));
            address market = lidoARM.activeMarket();
            if (market != address(0)) bal += IERC4626(market).maxWithdraw(address(lidoARM));
            uint256 reserved = lidoARM.reservedWithdrawLiquidity();
            uint256 available = bal > reserved ? bal - reserved : 0;
            maxAmountOut = available < buyLiqRemaining ? available : buyLiqRemaining;
        } else {
            // ARM pays base: min(base balance, sellLiquidityRemaining)
            uint256 bal = IERC20(baseAsset).balanceOf(address(lidoARM));
            maxAmountOut = bal < sellLiqRemaining ? bal : sellLiqRemaining;
        }
        // Buy side: even a 0-amount swap reverts when reserved > balance (no market to cover).
        if (buyOrSell) vm.assume(maxAmountOut > 0);

        // 2. Bound desired output, then reverse-calculate amountIn
        uint256 boundedOut = _bound(amount, 0, maxAmountOut);
        uint256 amountIn;
        if (buyOrSell) {
            // amountOut (WETH) = convertToAssets(amountIn) * buyPrice / PRICE_SCALE
            // → convertToAssets(amountIn) = amountOut * PRICE_SCALE / buyPrice
            uint256 inLiquidityTerms = boundedOut * PRICE_SCALE / buyPrice;
            amountIn = stETHOrWstETH ? inLiquidityTerms : mockWstETH.getWstETHByStETH(inLiquidityTerms);
        } else {
            // amountOut (base) = convertToShares(amountIn) * PRICE_SCALE / sellPrice
            // → convertToShares(amountIn) = amountOut * sellPrice / PRICE_SCALE
            uint256 sharesNeeded = boundedOut * sellPrice / PRICE_SCALE;
            // convertToShares(amountIn) = sharesNeeded, invert to get amountIn (WETH)
            amountIn = stETHOrWstETH ? sharesNeeded : mockWstETH.getStETHByWstETH(sharesNeeded);
        }

        // 3. Deal tokenIn to swapper and execute
        if (tokenIn == address(wsteth)) {
            dealWsteth(grace, amountIn);
        } else if (tokenIn == address(steth)) {
            MockERC20(tokenIn).mint(grace, amountIn);
        } else {
            deal(tokenIn, grace, amountIn);
        }
        vm.prank(grace);
        uint256[] memory amounts =
            lidoARM.swapExactTokensForTokens(IERC20(tokenIn), IERC20(tokenOut), amountIn, 0, grace);

        // Ghost: track token flows and fees
        _trackSwapGhosts(baseAsset, buyOrSell, amounts[0], amounts[1]);

        if (consoleLogs) {
            string memory label =
                string.concat("Swap: ", vm.getLabel(tokenIn), " -> ", vm.getLabel(tokenOut), ", amount=%18e");
            console.log(label, amountIn);
        }
    }

    function targetSwapTokensForExactTokens(uint88 amount, bool stETHOrWstETH, bool buyOrSell)
        public
        ensureSharePriceNotDecreased
    {
        address baseAsset = stETHOrWstETH ? address(steth) : address(wsteth);
        // buyOrSell: true = ARM buys base asset (trader sends base, gets WETH)
        //            false = ARM sells base asset (trader sends WETH, gets base)
        address tokenIn = buyOrSell ? baseAsset : address(weth);
        address tokenOut = buyOrSell ? address(weth) : baseAsset;

        (uint128 buyPrice, uint128 sellPrice, uint128 buyLiqRemaining, uint128 sellLiqRemaining,,,,,) =
            lidoARM.baseAssetConfigs(baseAsset);

        // 1. Max output the ARM can deliver
        uint256 maxAmountOut;
        if (buyOrSell) {
            uint256 bal = weth.balanceOf(address(lidoARM));
            address market = lidoARM.activeMarket();
            if (market != address(0)) bal += IERC4626(market).maxWithdraw(address(lidoARM));
            uint256 reserved = lidoARM.reservedWithdrawLiquidity();
            uint256 available = bal > reserved ? bal - reserved : 0;
            maxAmountOut = available < buyLiqRemaining ? available : buyLiqRemaining;
        } else {
            uint256 bal = IERC20(baseAsset).balanceOf(address(lidoARM));
            maxAmountOut = bal < sellLiqRemaining ? bal : sellLiqRemaining;
        }
        if (buyOrSell) vm.assume(maxAmountOut > 0);

        // 2. Bound exact output
        uint256 boundedOut = _bound(amount, 0, maxAmountOut);

        // 3. Calculate amountInMax matching the contract's formula (+3 wei buffer)
        uint256 amountInMax;
        if (buyOrSell) {
            // Contract: convertToShares(amountOut) * PRICE_SCALE / buyPrice + 3
            uint256 converted = stETHOrWstETH ? boundedOut : mockWstETH.getWstETHByStETH(boundedOut);
            amountInMax = converted * PRICE_SCALE / buyPrice + 3;
        } else {
            // Contract: convertToAssets(amountOut) * sellPrice / PRICE_SCALE + 3
            uint256 converted = stETHOrWstETH ? boundedOut : mockWstETH.getStETHByWstETH(boundedOut);
            amountInMax = converted * sellPrice / PRICE_SCALE + 3;
        }

        // 4. Deal tokenIn to swapper and execute
        if (tokenIn == address(wsteth)) {
            dealWsteth(grace, amountInMax);
        } else if (tokenIn == address(steth)) {
            MockERC20(tokenIn).mint(grace, amountInMax);
        } else {
            deal(tokenIn, grace, amountInMax);
        }
        vm.prank(grace);
        uint256[] memory amounts =
            lidoARM.swapTokensForExactTokens(IERC20(tokenIn), IERC20(tokenOut), boundedOut, amountInMax, grace);

        // Ghost: track token flows and fees
        _trackSwapGhosts(baseAsset, buyOrSell, amounts[0], amounts[1]);

        if (consoleLogs) {
            string memory label =
                string.concat("SwapExact: ", vm.getLabel(tokenIn), " -> ", vm.getLabel(tokenOut), ", out=%18e");
            console.log(label, boundedOut);
        }
    }

    ////////////////////////////////////////////////////
    /// --- LIQUIDITY PROVIDERS
    ////////////////////////////////////////////////////
    function targetDeposit(uint128 amount, uint16 from) public ensureSharePriceNotDecreased {
        (address user, uint256 balance) = selectUserWithLiqudity(from);
        vm.assume(user != address(0)); // Ensure we found a user with liquidity

        // Mirror AbstractARM._deposit's Insolvent() guard: at the asset floor (totalAssets() clamped to
        // MIN_LIQUIDITY == 1e12) deposits revert when any senior liability (accrued fees or reserved LP
        // redeems) is outstanding. Skip those inputs so strict-mode fuzzing does not fail on the revert.
        vm.assume(
            lidoARM.totalAssets() > 1e12 || (lidoARM.feesAccrued() == 0 && lidoARM.reservedWithdrawLiquidity() == 0)
        );

        // Bound amount
        uint256 boundedAmount = _bound(amount, MINIMUM_DEPOSIT, uint128(balance));
        vm.prank(user);
        lidoARM.deposit(boundedAmount);
        sum_weth_deposit += boundedAmount;
        ghost_userDeposited[user] += boundedAmount;
        ghost_userDepositCount[user] += 1;

        // Log deposit details
        if (consoleLogs) {
            console.log("Deposit: user=%s, amount=%18e", vm.getLabel(user), boundedAmount);
        }
    }

    function targetRequestRedeem(uint128 shares, uint16 from) public ensureSharePriceNotDecreased {
        (address user, uint256 balance) = selectUserWithShares(from);
        vm.assume(user != address(0)); // Ensure we found a user with shares to redeem

        // Bound shares
        uint256 boundedShares = _bound(shares, MIN_SHARES_TO_REQUEST, uint128(balance));
        vm.prank(user);
        (uint256 requestId, uint256 requestAssets) = lidoARM.requestRedeem(boundedShares);
        ghost_requestCounter++;
        sum_shares_requested += boundedShares;

        // Log redeem request details
        if (consoleLogs) {
            console.log("Request Redeem: user=%s, shares=%18e", vm.getLabel(user), boundedShares);
        }

        _pendingRequestIds.push(requestId); // Track the pending request ID for future claim testing
        shuffle(_pendingRequestIds, from); // Shuffle pending request IDs to ensure randomness in claim
    }

    function targetClaimRedeem(uint16 seed) public ensureSharePriceNotDecreased {
        (address user, uint256 requestId, uint256 positionInList) = selectUserWithPendingRequest();
        vm.assume(user != address(0));

        uint256 reqShares = lidoARM.withdrawalRequestShares(requestId);

        // claimable() passing does not guarantee claimRedeem succeeds (known limitation, see PR#247).
        // The share-based FIFO gate can pass while the market lacks liquidity for this specific request.
        vm.prank(user);
        try lidoARM.claimRedeem(requestId) returns (uint256 claimedAssets) {
            sum_shares_claimed += reqShares;
            sum_weth_userClaimed += claimedAssets;
            ghost_userClaimed[user] += claimedAssets;

            removeFromList(_pendingRequestIds, positionInList);
            shuffle(_pendingRequestIds, seed);

            if (consoleLogs) {
                console.log("Claim Redeem: user=%s, requestId=%d", vm.getLabel(user), requestId);
            }
        } catch {
            if (consoleLogs) {
                console.log("Claim Redeem SKIPPED (insufficient liquidity): requestId=%d", requestId);
            }
        }
    }

    function targetTransferShares(uint128 amount, uint16 from, uint16 to) public ensureSharePriceNotDecreased {
        (address source, uint256 balance) = selectUserWithShares(from);
        vm.assume(source != address(0));

        // Pick a different LP as destination
        address dest = lps[uint256(to) % LP_COUNT];
        vm.assume(dest != source);

        uint256 boundedAmount = _bound(amount, 1, balance);
        uint256 transferValue = lidoARM.convertToAssets(boundedAmount);
        ghost_userTransferOutValue[source] += transferValue;
        ghost_userTransferInValue[dest] += transferValue;

        vm.prank(source);
        lidoARM.transfer(dest, boundedAmount);

        if (consoleLogs) {
            console.log("TransferShares: %s -> %s, amount=%18e", vm.getLabel(source), vm.getLabel(dest), boundedAmount);
        }
    }

    function targetDonate(uint88 amount, uint8 tokenSeed) public ensureSharePriceNotDecreased {
        address donor = address(0xd074);
        uint256 boundedAmount = _bound(amount, 1, 1 ether);

        uint256 pick = uint256(tokenSeed) % 3;
        if (pick == 0) {
            deal(address(weth), donor, boundedAmount);
            vm.prank(donor);
            weth.transfer(address(lidoARM), boundedAmount);
        } else if (pick == 1) {
            MockERC20(address(steth)).mint(donor, boundedAmount);
            vm.prank(donor);
            steth.transfer(address(lidoARM), boundedAmount);
        } else {
            dealWsteth(donor, boundedAmount);
            vm.prank(donor);
            wsteth.transfer(address(lidoARM), boundedAmount);
        }

        // Ghost: track donations
        if (pick == 0) sum_weth_donated += boundedAmount;
        else if (pick == 1) sum_steth_donated += boundedAmount;
        else sum_wsteth_donated += boundedAmount;

        if (consoleLogs) {
            string[3] memory names = ["WETH", "stETH", "wstETH"];
            console.log(string.concat("Donate: ", names[pick], " %18e"), boundedAmount);
        }
    }

    ////////////////////////////////////////////////////
    /// --- BASE ASSET REDEMPTIONS
    ////////////////////////////////////////////////////
    function targetRequestBaseWithdrawal(uint128 amount, bool stETHOrWstETH) public ensureSharePriceNotDecreased {
        address baseAsset = stETHOrWstETH ? address(steth) : address(wsteth);
        uint256 bal = IERC20(baseAsset).balanceOf(address(lidoARM));
        vm.assume(bal > 0);

        uint256 boundedAmount = _bound(amount, 1, bal);

        vm.prank(operator);
        (uint256 sharesRequested, uint256 assetsExpected) = lidoARM.requestBaseAssetRedeem(baseAsset, boundedAmount);

        // Ghost: track base asset outflows
        if (stETHOrWstETH) sum_steth_baseRedeemRequested += boundedAmount;
        else sum_wsteth_baseRedeemRequested += boundedAmount;

        // Track shares in the per-asset FIFO queue
        if (stETHOrWstETH) {
            _pendingBaseRedeemShares_stETH.push(sharesRequested);
        } else {
            _pendingBaseRedeemShares_wstETH.push(sharesRequested);
        }

        if (consoleLogs) {
            string memory asset = stETHOrWstETH ? "stETH" : "wstETH";
            console.log(string.concat("RequestBaseWithdrawal [", asset, "]: %18e"), boundedAmount);
        }
    }

    function targetClaimBaseWithdrawals(uint8 count, bool stETHOrWstETH) public ensureSharePriceNotDecreased {
        address baseAsset = stETHOrWstETH ? address(steth) : address(wsteth);
        uint256[] storage queue = stETHOrWstETH ? _pendingBaseRedeemShares_stETH : _pendingBaseRedeemShares_wstETH;
        vm.assume(queue.length > 0);

        // Pick how many FIFO requests to claim (1 to queue.length)
        uint256 claimCount = _bound(count, 1, queue.length);

        // Sum the shares for the first claimCount requests
        uint256 totalShares;
        for (uint256 i; i < claimCount; i++) {
            totalShares += queue[i];
        }

        vm.prank(operator);
        (uint256 claimed,, uint256 received) = lidoARM.claimBaseAssetRedeem(baseAsset, totalShares);
        sum_weth_baseRedeemClaimed += received;

        // Remove claimed entries from the front of the queue
        for (uint256 i; i < queue.length - claimCount; i++) {
            queue[i] = queue[i + claimCount];
        }
        for (uint256 i; i < claimCount; i++) {
            queue.pop();
        }

        if (consoleLogs) {
            string memory asset = stETHOrWstETH ? "stETH" : "wstETH";
            console.log(string.concat("ClaimBaseWithdrawals [", asset, "]: claimed=%18e"), claimed);
            console.log("                                   received=%18e", received);
        }
    }

    ////////////////////////////////////////////////////
    /// --- LIQUIDITY MANAGMENT
    ////////////////////////////////////////////////////
    function targetSetActiveMarket(uint16 seed) public ensureSharePriceNotDecreased {
        address current = lidoARM.activeMarket();
        address[3] memory candidates = [address(0), address(mockERC4626Market_A), address(mockERC4626Market_B)];

        // Pick among the 2 candidates that differ from current
        uint256 s = seed;
        address picked = candidates[s % 3];
        if (picked == current) picked = candidates[(s + 1) % 3];

        // Switching away from a market redeems ALL shares via balanceOf. Skip the call if that full
        // redeem would revert: either the market can't cover it (maxRedeem < balanceOf), or the shares
        // are dust worth 0 assets (convertToAssets == 0), which reverts with ZERO_ASSETS in ERC4626.redeem.
        // Both are documented operational edge cases the operator handles off-chain (see setActiveMarket).
        if (current != address(0)) {
            uint256 shares = IERC4626(current).balanceOf(address(lidoARM));
            vm.assume(
                shares == 0
                    || (shares <= IERC4626(current).maxRedeem(address(lidoARM))
                        && IERC4626(current).convertToAssets(shares) > 0)
            );
        }

        vm.prank(operator);
        lidoARM.setActiveMarket(picked);

        if (consoleLogs) {
            console.log("SetActiveMarket: %s", picked == address(0) ? "none" : vm.getLabel(picked));
        }
    }

    function targetAllocate() public ensureSharePriceNotDecreased {
        vm.assume(lidoARM.activeMarket() != address(0));

        (int256 target, int256 actual) = lidoARM.allocate();

        if (consoleLogs) {
            console.log("Allocate: target=%d", target);
            console.log("          actual=%d", actual);
        }
    }

    function targetSetARMBuffer(uint16 seed) public ensureSharePriceNotDecreased {
        uint256 picked = uint256(keccak256(abi.encodePacked(seed))) % (1e18 + 1);
        uint256 bps = picked / 0.0001e18;

        vm.prank(operator);
        lidoARM.setARMBuffer(picked);

        if (consoleLogs) {
            console.log("SetARMBuffer: %d.%d%d%%", bps / 100, (bps / 10) % 10, bps % 10);
        }
    }

    ////////////////////////////////////////////////////
    /// --- LIDO (external protocol simulation)
    ////////////////////////////////////////////////////
    function targetRebase(uint16 seed) public ensureSharePriceNotDecreased {
        // Simulate stETH rebase by minting proportional stETH to all holders.
        // Max 10% APR → max ~0.027% per day → 27 bps per call.
        uint256 rebaseBps = uint256(keccak256(abi.encodePacked(seed))) % 28;

        address[3] memory holders = [address(lidoARM), address(wsteth), address(lidoWithdrawalQueue)];
        for (uint256 i; i < holders.length; i++) {
            uint256 bal = steth.balanceOf(holders[i]);
            uint256 reward = bal * rebaseBps / 10_000;
            if (reward == 0) continue;
            MockERC20(address(steth)).mint(holders[i], reward);
            if (holders[i] == address(lidoARM)) sum_steth_rebased += reward;
        }

        if (consoleLogs) {
            console.log("Rebase: 0.%d%d%%", rebaseBps / 10, rebaseBps % 10);
        }
    }

    ////////////////////////////////////////////////////
    /// --- ERC4626 MARKETS (external protocol simulation)
    ////////////////////////////////////////////////////
    function targetSetUtilizationRate(uint8 seed, bool marketA) public ensureSharePriceNotDecreased {
        MockMorpho market = marketA ? mockERC4626Market_A : mockERC4626Market_B;

        // Hash the seed to get uniform distribution across the range, avoiding _bound's edge bias
        uint256 rate = uint256(keccak256(abi.encodePacked(seed))) % (1e18 + 1);
        market.setUtilizationRate(rate);

        if (consoleLogs) {
            string memory label = marketA ? "A" : "B";
            uint256 bps = rate * 10_000 / 1e18;
            console.log(
                string.concat("SetUtilizationRate [", label, "]: %d.%d%d%%"), bps / 100, (bps / 10) % 10, bps % 10
            );
        }
    }

    function targetMarketDeposit(uint128 amount, bool marketA) public ensureSharePriceNotDecreased {
        MockMorpho market = marketA ? mockERC4626Market_A : mockERC4626Market_B;
        uint256 bal = weth.balanceOf(hanna);
        vm.assume(bal > 0);

        uint256 boundedAmount = _bound(amount, 1, bal);
        // With a share price >= 1, a tiny deposit can round down to 0 shares, which reverts with
        // ZERO_SHARES in ERC4626.deposit. Skip those amounts (a supplier would never deposit dust).
        vm.assume(market.previewDeposit(boundedAmount) > 0);
        vm.prank(hanna);
        market.deposit(boundedAmount, hanna);

        if (consoleLogs) {
            string memory label = marketA ? "A" : "B";
            console.log(string.concat("MarketDeposit [", label, "]: %18e"), boundedAmount);
        }
    }

    function targetMarketWithdraw(uint128 amount, bool marketA) public ensureSharePriceNotDecreased {
        MockMorpho market = marketA ? mockERC4626Market_A : mockERC4626Market_B;
        uint256 maxW = market.maxWithdraw(hanna);
        vm.assume(maxW > 0);

        uint256 boundedAmount = _bound(amount, 1, maxW);
        vm.prank(hanna);
        market.withdraw(boundedAmount, hanna, hanna);

        if (consoleLogs) {
            string memory label = marketA ? "A" : "B";
            console.log(string.concat("MarketWithdraw [", label, "]: %18e"), boundedAmount);
        }
    }

    function targetMarketTransferRewards(uint16 seed, bool marketA) public ensureSharePriceNotDecreased {
        MockMorpho market = marketA ? mockERC4626Market_A : mockERC4626Market_B;
        uint256 totalAssets = market.totalAssets();
        vm.assume(totalAssets > 0);

        // Snapshot ARM's share value before yield
        uint256 armValueBefore =
            IERC4626(address(market)).convertToAssets(IERC4626(address(market)).balanceOf(address(lidoARM)));

        // 30% APR max → ~0.082% per day → 82 bps per call
        uint256 rewardBps = uint256(keccak256(abi.encodePacked(seed))) % 83;
        uint256 reward = totalAssets * rewardBps / 10_000;
        if (reward == 0) return;

        deal(address(weth), address(market), weth.balanceOf(address(market)) + reward);

        // Track yield accrued to ARM
        uint256 armValueAfter =
            IERC4626(address(market)).convertToAssets(IERC4626(address(market)).balanceOf(address(lidoARM)));
        if (armValueAfter > armValueBefore) sum_weth_marketYield += armValueAfter - armValueBefore;

        if (consoleLogs) {
            string memory label = marketA ? "A" : "B";
            console.log(string.concat("MarketRewards [", label, "]: %18e (+%d bps)"), reward, rewardBps);
        }
    }

    ////////////////////////////////////////////////////
    /// --- PRICES AND FEES MANAGEMENT
    ////////////////////////////////////////////////////
    function targetSetPrices(bool stETHOrWstETH, uint16 buySeed, uint16 sellSeed, uint128 buyAmount, uint128 sellAmount)
        public
        ensureSharePriceNotDecreased
    {
        address baseAsset = stETHOrWstETH ? address(steth) : address(wsteth);
        (,,,, uint128 crossPrice,,,,) = lidoARM.baseAssetConfigs(baseAsset);

        // buyPrice in [MINIMUM_BUY_PRICE, crossPrice - 1)
        // sellPrice in [crossPrice, MINUMUM_SELL_PRICE]
        uint256 buyRange = crossPrice - 1 - MINIMUM_BUY_PRICE;
        uint256 sellRange = MINUMUM_SELL_PRICE - crossPrice;
        uint256 buyPrice = MINIMUM_BUY_PRICE + uint256(keccak256(abi.encodePacked(buySeed))) % (buyRange + 1);
        uint256 sellPrice = crossPrice + uint256(keccak256(abi.encodePacked(sellSeed))) % (sellRange + 1);

        vm.prank(operator);
        lidoARM.setPrices(baseAsset, buyPrice, sellPrice, buyAmount, sellAmount);

        if (consoleLogs) {
            string memory asset = stETHOrWstETH ? "stETH" : "wstETH";
            console.log(string.concat("SetPrices [", asset, "]: buy=%18e"), buyPrice);
            console.log("                    sell=%18e", sellPrice);
        }
    }

    function targetSetCrossPrice(bool stETHOrWstETH, uint16 seed) public updateSharePrice {
        address baseAsset = stETHOrWstETH ? address(steth) : address(wsteth);
        (uint128 buyPrice, uint128 sellPrice,,, uint128 currentCross,,,,) = lidoARM.baseAssetConfigs(baseAsset);

        // crossPrice in [PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION, PRICE_SCALE]
        // Must also satisfy: buyPrice < crossPrice <= sellPrice
        uint256 lo = PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION;
        uint256 hi = PRICE_SCALE;
        // Tighten to respect existing buy/sell prices
        if (buyPrice + 1 > lo) lo = buyPrice + 1;
        if (sellPrice < hi) hi = sellPrice;
        vm.assume(lo <= hi);

        // Lowering crossPrice reverts if ARM has base asset exposure >= MIN_TOTAL_SUPPLY.
        (,,,,, uint128 pendingRedeem,,, address adapter) = lidoARM.baseAssetConfigs(baseAsset);
        uint256 baseBalance = IERC20(baseAsset).balanceOf(address(lidoARM));
        uint256 exposure = IAssetAdapter(adapter).convertToAssets(baseBalance) + pendingRedeem;
        if (exposure >= MIN_TOTAL_SUPPLY && currentCross > lo) lo = currentCross;
        vm.assume(lo <= hi);

        uint256 crossRange = hi - lo;
        uint256 newCrossPrice = lo + uint256(keccak256(abi.encodePacked(seed))) % (crossRange + 1);

        vm.prank(governor);
        lidoARM.setCrossPrice(baseAsset, newCrossPrice);

        if (consoleLogs) {
            string memory asset = stETHOrWstETH ? "stETH" : "wstETH";
            console.log(string.concat("SetCrossPrice [", asset, "]: %36e"), newCrossPrice);
        }
    }

    function targetCollectFees() public ensureSharePriceNotDecreased {
        uint256 fees = lidoARM.feesAccrued();
        uint256 reserved = lidoARM.reservedWithdrawLiquidity();
        uint256 bal = weth.balanceOf(address(lidoARM));
        vm.assume(fees > 0 && fees + reserved <= bal);

        lidoARM.collectFees();
        sum_fees_collected += fees;
        sum_weth_feesCollected += fees;

        if (consoleLogs) {
            console.log("CollectFees: %18e", fees);
        }
    }

    function targetSetFee(uint16 seed) public ensureSharePriceNotDecreased {
        // Fee in [0, FEE_SCALE / 2] (0% to 50%)
        uint256 newFee = uint256(keccak256(abi.encodePacked(seed))) % (FEE_SCALE / 2 + 1);

        // setFee calls collectFees internally, which reverts if insufficient liquidity
        uint256 fees = lidoARM.feesAccrued();
        uint256 reserved = lidoARM.reservedWithdrawLiquidity();
        uint256 bal = weth.balanceOf(address(lidoARM));
        vm.assume(fees == 0 || fees + reserved <= bal);

        vm.prank(governor);
        lidoARM.setFee(newFee);

        if (consoleLogs) {
            console.log("SetFee: %d bps", newFee);
        }

        // setFee calls collectFees internally
        if (fees > 0) {
            sum_fees_collected += fees;
            sum_weth_feesCollected += fees;
        }
    }

    ////////////////////////////////////////////////////
    /// --- GHOST TRACKING HELPERS
    ////////////////////////////////////////////////////
    function _trackSwapGhosts(address baseAsset, bool buyOrSell, uint256 amtIn, uint256 amtOut) internal {
        if (buyOrSell) {
            // ARM buys base (trader sends base, gets WETH)
            if (baseAsset == address(steth)) sum_steth_swapIn += amtIn;
            else sum_wsteth_swapIn += amtIn;
            sum_weth_swapOut += amtOut;
            sum_weth_buyside_out += amtOut;

            // Track the realized buy-side gain and fee using the same conversion and rounding as AbstractARM.
            (,,,, uint128 crossPrice,, bool peggedToLiquidityAsset,, address adapter) =
                lidoARM.baseAssetConfigs(baseAsset);
            uint256 convertedAmountIn = peggedToLiquidityAsset ? amtIn : IAssetAdapter(adapter).convertToAssets(amtIn);
            uint256 realizedAssets = convertedAmountIn * crossPrice / PRICE_SCALE;
            uint256 gain = realizedAssets > amtOut ? realizedAssets - amtOut : 0;
            sum_buyside_realized_gain += gain;
            sum_fees_accrued += gain * uint256(lidoARM.fee()) / FEE_SCALE;
        } else {
            // ARM sells base (trader sends WETH, gets base)
            sum_weth_swapIn += amtIn;
            if (baseAsset == address(steth)) sum_steth_swapOut += amtOut;
            else sum_wsteth_swapOut += amtOut;
        }
    }
}
