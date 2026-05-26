// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {console} from "forge-std/console.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

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
    function targetSwapExactTokensForTokens(uint88 amount, bool stETHOrWstETH, bool buyOrSell) public {
        address baseAsset = stETHOrWstETH ? address(steth) : address(wsteth);
        // buyOrSell: true = ARM buys base asset (trader sends base, gets WETH)
        //            false = ARM sells base asset (trader sends WETH, gets base)
        address tokenIn = buyOrSell ? baseAsset : address(weth);
        address tokenOut = buyOrSell ? address(weth) : baseAsset;

        (uint128 buyPrice, uint128 sellPrice, uint128 buyLiqRemaining, uint128 sellLiqRemaining,,,,) =
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
        lidoARM.swapExactTokensForTokens(IERC20(tokenIn), IERC20(tokenOut), amountIn, 0, grace);

        if (consoleLogs) {
            string memory label =
                string.concat("Swap: ", vm.getLabel(tokenIn), " -> ", vm.getLabel(tokenOut), ", amount=%18e");
            console.log(label, amountIn);
        }
    }

    function targetSwapTokensForExactTokens(uint88 amount, bool stETHOrWstETH, bool buyOrSell) public {
        address baseAsset = stETHOrWstETH ? address(steth) : address(wsteth);
        // buyOrSell: true = ARM buys base asset (trader sends base, gets WETH)
        //            false = ARM sells base asset (trader sends WETH, gets base)
        address tokenIn = buyOrSell ? baseAsset : address(weth);
        address tokenOut = buyOrSell ? address(weth) : baseAsset;

        (uint128 buyPrice, uint128 sellPrice, uint128 buyLiqRemaining, uint128 sellLiqRemaining,,,,) =
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
        lidoARM.swapTokensForExactTokens(IERC20(tokenIn), IERC20(tokenOut), boundedOut, amountInMax, grace);

        if (consoleLogs) {
            string memory label =
                string.concat("SwapExact: ", vm.getLabel(tokenIn), " -> ", vm.getLabel(tokenOut), ", out=%18e");
            console.log(label, boundedOut);
        }
    }

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

    function targetClaimRedeem(uint16 seed) public {
        (address user, uint256 requestId, uint256 positionInList) = selectUserWithPendingRequest();
        vm.assume(user != address(0)); // Ensure we found a user with a pending redeem request

        vm.prank(user);
        lidoARM.claimRedeem(requestId);

        // Log claim redeem details
        if (consoleLogs) {
            console.log("Claim Redeem: user=%s, requestId=%d", vm.getLabel(user), requestId);
        }

        // Remove the claimed request ID from the pending list
        removeFromList(_pendingRequestIds, positionInList);
        shuffle(_pendingRequestIds, seed); // Shuffle pending request IDs to ensure randomness in future claim attempts
    }

    ////////////////////////////////////////////////////
    /// --- BASE ASSET REDEMPTIONS
    ////////////////////////////////////////////////////
    function targetRequestBaseWithdrawal(uint128 amount, bool stETHOrWstETH) public {
        address baseAsset = stETHOrWstETH ? address(steth) : address(wsteth);
        uint256 bal = IERC20(baseAsset).balanceOf(address(lidoARM));
        vm.assume(bal > 0);

        uint256 boundedAmount = _bound(amount, 1, bal);

        vm.prank(operator);
        (uint256 sharesRequested,) = lidoARM.requestBaseAssetRedeem(baseAsset, boundedAmount);

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

    function targetClaimBaseWithdrawals(uint8 count, bool stETHOrWstETH) public {
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
    function targetSetActiveMarket(uint16 seed) public {
        address current = lidoARM.activeMarket();
        address[3] memory candidates = [address(0), address(mockERC4626Market_A), address(mockERC4626Market_B)];

        // Pick among the 2 candidates that differ from current
        uint256 s = seed;
        address picked = candidates[s % 3];
        if (picked == current) picked = candidates[(s + 1) % 3];

        vm.prank(operator);
        lidoARM.setActiveMarket(picked);

        if (consoleLogs) {
            console.log("SetActiveMarket: %s", picked == address(0) ? "none" : vm.getLabel(picked));
        }
    }

    function targetAllocate() public {
        vm.assume(lidoARM.activeMarket() != address(0));

        (int256 target, int256 actual) = lidoARM.allocate();

        if (consoleLogs) {
            console.log("Allocate: target=%d", target);
            console.log("          actual=%d", actual);
        }
    }

    function targetSetARMBuffer(uint16 seed) public {
        // Round to 0.01% increments: gives values like 0%, 3.57%, 17.42%, 84.01%, etc.
        uint256 bps = _bound(seed, 0, 10_000);
        uint256 picked = bps * 0.0001e18;

        vm.prank(operator);
        lidoARM.setARMBuffer(picked);

        if (consoleLogs) {
            console.log("SetARMBuffer: %d.%d%d%%", bps / 100, (bps / 10) % 10, bps % 10);
        }
    }

    ////////////////////////////////////////////////////
    /// --- REDEMPTION MANAGMENT
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    /// --- PRICES AND FEES MANAGEMENT
    ////////////////////////////////////////////////////
    function targetSetPrices(bool stETHOrWstETH, uint16 buySeed, uint16 sellSeed, uint128 buyAmount, uint128 sellAmount)
        public
    {
        address baseAsset = stETHOrWstETH ? address(steth) : address(wsteth);
        (,,,, uint128 crossPrice,,,) = lidoARM.baseAssetConfigs(baseAsset);

        // buyPrice in [MINIMUM_BUY_PRICE, crossPrice - 1)
        // sellPrice in [crossPrice, MINUMUM_SELL_PRICE]
        uint256 buyPrice = _bound(buySeed, MINIMUM_BUY_PRICE, crossPrice - 1);
        uint256 sellPrice = _bound(sellSeed, crossPrice, MINUMUM_SELL_PRICE);

        vm.prank(operator);
        lidoARM.setPrices(baseAsset, buyPrice, sellPrice, buyAmount, sellAmount);

        if (consoleLogs) {
            string memory asset = stETHOrWstETH ? "stETH" : "wstETH";
            console.log(string.concat("SetPrices [", asset, "]: buy=%18e"), buyPrice);
            console.log("                    sell=%18e", sellPrice);
        }
    }

    function targetSetCrossPrice(bool stETHOrWstETH, uint16 seed) public {
        address baseAsset = stETHOrWstETH ? address(steth) : address(wsteth);
        (uint128 buyPrice, uint128 sellPrice,,, uint128 currentCross,,,) = lidoARM.baseAssetConfigs(baseAsset);

        // crossPrice in [PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION, PRICE_SCALE]
        // Must also satisfy: buyPrice < crossPrice <= sellPrice
        uint256 lo = PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION;
        uint256 hi = PRICE_SCALE;
        // Tighten to respect existing buy/sell prices
        if (buyPrice + 1 > lo) lo = buyPrice + 1;
        if (sellPrice < hi) hi = sellPrice;
        vm.assume(lo <= hi);

        // Lowering crossPrice reverts if ARM has base asset exposure >= MIN_TOTAL_SUPPLY.
        (,,,,, uint120 pendingRedeem,, address adapter) = lidoARM.baseAssetConfigs(baseAsset);
        uint256 baseBalance = IERC20(baseAsset).balanceOf(address(lidoARM));
        uint256 exposure = IAssetAdapter(adapter).convertToAssets(baseBalance) + pendingRedeem;
        if (exposure >= MIN_TOTAL_SUPPLY && currentCross > lo) lo = currentCross;
        vm.assume(lo <= hi);

        uint256 newCrossPrice = _bound(seed, lo, hi);

        vm.prank(governor);
        lidoARM.setCrossPrice(baseAsset, newCrossPrice);

        if (consoleLogs) {
            string memory asset = stETHOrWstETH ? "stETH" : "wstETH";
            console.log(string.concat("SetCrossPrice [", asset, "]: %36e"), newCrossPrice);
        }
    }

    function targetCollectFees() public {
        uint256 fees = lidoARM.feesAccrued();
        uint256 reserved = lidoARM.reservedWithdrawLiquidity();
        uint256 bal = weth.balanceOf(address(lidoARM));
        vm.assume(fees > 0 && fees + reserved <= bal);

        lidoARM.collectFees();

        if (consoleLogs) {
            console.log("CollectFees: %18e", fees);
        }
    }

    function targetSetFee(uint16 seed) public {
        // Fee in [0, FEE_SCALE / 2] (0% to 50%)
        uint256 newFee = _bound(seed, 0, FEE_SCALE / 2);

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
    }
}
