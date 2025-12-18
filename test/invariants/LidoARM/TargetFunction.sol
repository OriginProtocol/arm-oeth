// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Test imports
import {Properties} from "test/invariants/LidoARM/Properties.sol";

abstract contract TargetFunction is Properties {
    ////////////////////////////////////////////////////
    /// --- SWAPS
    ////////////////////////////////////////////////////
    function handler_swapExactTokensForTokens(uint8 account, bool stETHForWETH, uint80 amount) public {
        address[] memory path = new address[](2);
        path[0] = stETHForWETH ? address(steth) : address(weth);
        path[1] = stETHForWETH ? address(weth) : address(steth);

        // Select a random user
        address user = swaps[account % swaps.length];

        // Cache estimated amount out
        uint256 estimatedAmountOut = estimateAmountOut(IERC20(path[0]), amount);

        // Prank the user
        vm.prank(user);
        uint256[] memory amounts = lidoARM.swapExactTokensForTokens({
            amountIn: amount, amountOutMin: 0, path: path, to: address(user), deadline: block.timestamp
        });

        // Update ghost
        ghost_swap_C = amounts[0] == amount;
        ghost_swap_D = amounts[1] == estimatedAmountOut;
        stETHForWETH ? sum_steth_swap_in += amounts[0] : sum_weth_swap_in += amounts[0];
        stETHForWETH ? sum_weth_swap_out += amounts[1] : sum_steth_swap_out += amounts[1];
    }

    function handler_swapTokensForExactTokens(uint8 account, bool stETHForWETH, uint80 amount) public {
        address[] memory path = new address[](2);
        path[0] = stETHForWETH ? address(steth) : address(weth);
        path[1] = stETHForWETH ? address(weth) : address(steth);

        // Select a random user
        address user = swaps[account % swaps.length];

        // Cache estimated amount in
        uint256 estimatedAmountIn = estimateAmountIn(IERC20(path[1]), amount);

        // Prank the user
        vm.prank(user);
        uint256[] memory amounts = lidoARM.swapTokensForExactTokens({
            amountOut: amount, amountInMax: type(uint256).max, path: path, to: address(user), deadline: block.timestamp
        });

        // Update ghost
        ghost_swap_C = amounts[0] == estimatedAmountIn;
        ghost_swap_D = amounts[1] == amount;
        stETHForWETH ? sum_steth_swap_in += amounts[0] : sum_weth_swap_in += amounts[0];
        stETHForWETH ? sum_weth_swap_out += amounts[1] : sum_steth_swap_out += amounts[1];
    }

    ////////////////////////////////////////////////////
    /// --- LIQUIDITY PROVIDERS
    ////////////////////////////////////////////////////
    mapping(address => uint256[]) public requests;

    function handler_deposit(uint8 account, uint80 amount) public {
        // Select a random user
        address user = lps[account % lps.length];

        // Cache preview deposit
        uint256 expectedShares = lidoARM.previewDeposit(amount);

        // Prank the user
        vm.prank(user);
        uint256 shares = lidoARM.deposit(amount);

        // Update ghost
        sum_weth_deposit += amount;
        ghost_lp_D = shares == expectedShares;
    }

    function handler_requestRedeem(uint8 account, uint80 shares) public {
        address user;
        uint256 len = lps.length;
        // Select a random user with non-zero shares
        for (uint256 i = account; i < account + len; i++) {
            address user_ = lps[i % len];
            if (lidoARM.balanceOf(user_) > 0) {
                user = user_;
                break;
            }
        }

        if (user == address(0)) {
            return;
        }

        // Cache preview redeem
        uint256 expectedAmount = lidoARM.previewRedeem(shares);

        // Prank the user
        vm.prank(user);

        // Request redeem
        (uint256 id, uint256 amount) = lidoARM.requestRedeem(shares);

        // Update state
        requests[user].push(id);
        sum_weth_request += amount;
        ghost_lp_E = amount == expectedAmount;
        ghost_requestCounter++;
    }

    function handler_claimRedeem(uint8 account, uint256 id) public {
        address user;
        uint256 requestId;
        uint256 len = lps.length;
        // Select a random user with a request
        for (uint256 i = account; i < account + len; i++) {
            address user_ = lps[i % len];
            uint256 requestCount = requests[user_].length;
            if (requestCount > 0) {
                user = user_;
                requestId = id % requestCount;
                break;
            }
        }

        // Timejump to request deadline
        skip(lidoARM.claimDelay());

        // Prank the user
        vm.prank(user);

        // Claim redeem
        uint256 amount = lidoARM.claimRedeem(requestId);

        // Jump back to current time, to avoid issues with other tests
        rewind(lidoARM.claimDelay());

        // Update state
        for (uint256 i = 0; i < requests[user].length; i++) {
            // Get position of the requestId in the array
            if (requests[user][i] == requestId) {
                // Remove it from the list
                requests[user][i] = requests[user][requests[user].length - 1];
                requests[user].pop();
                break;
            }
        }

        // Update ghost
        sum_weth_withdraw += amount;
    }

    ////////////////////////////////////////////////////
    /// --- LIDO LIQUIDITY MANAGMENT
    ////////////////////////////////////////////////////
    uint256 constant MAX_BATCH_SIZE = 1_000 ether;
    uint256[] public lidoWithdrawRequests;

    function handler_requestLidoWithdrawals(uint80 amount) public {
        // Split the amount into 1k chunks
        uint256 batch = (amount + MAX_BATCH_SIZE - 1) / MAX_BATCH_SIZE; // Rounded up
        uint256[] memory amounts = new uint256[](batch);
        uint256 totalAmount = amount;
        for (uint256 i = 0; i < batch; i++) {
            if (totalAmount > MAX_BATCH_SIZE) {
                amounts[i] = MAX_BATCH_SIZE;
                totalAmount -= MAX_BATCH_SIZE;
            } else {
                amounts[i] = totalAmount;
                totalAmount = 0;
            }
        }

        // Prank Owner
        vm.prank(lidoARM.owner());
        uint256[] memory newLidoWithdrawRequests = lidoARM.requestLidoWithdrawals(amounts);

        // Update state
        for (uint256 i = 0; i < newLidoWithdrawRequests.length; i++) {
            lidoWithdrawRequests.push(newLidoWithdrawRequests[i]);
        }

        // Update ghost
        sum_steth_lido_requested += amount;
    }

    function handler_claimLidoWithdrawals(uint256 requestToClaimCount) public {
        uint256 len = lidoWithdrawRequests.length;
        requestToClaimCount = requestToClaimCount % len;

        // Select lidoWithdrawRequests
        uint256[] memory requestToClaim = new uint256[](requestToClaimCount);
        for (uint256 i; i < requestToClaimCount; i++) {
            requestToClaim[i] = lidoWithdrawRequests[i];
        }

        // As `claimLidoWithdrawals` doesn't send back the amount, we need to calculate it
        uint256 outstandingBefore = lidoARM.lidoWithdrawalQueueAmount();

        // Prank Owner
        vm.prank(lidoARM.owner());
        lidoARM.claimLidoWithdrawals(requestToClaim, new uint256[](0));

        uint256 outstandingAfter = lidoARM.lidoWithdrawalQueueAmount();
        uint256 diff = outstandingBefore - outstandingAfter;

        // Remove it from the list
        uint256[] memory newLidoWithdrawRequests = new uint256[](len - requestToClaimCount);
        for (uint256 i = requestToClaimCount; i < len; i++) {
            newLidoWithdrawRequests[i - requestToClaimCount] = lidoWithdrawRequests[i];
        }
        lidoWithdrawRequests = newLidoWithdrawRequests;

        // Update ghost
        sum_weth_lido_redeem += diff;
    }

    ////////////////////////////////////////////////////
    /// --- PRICES AND FEES MANAGEMENT
    ////////////////////////////////////////////////////
    uint256 constant MIN_FEES = 0;
    uint256 constant MAX_FEES = 5000;
    uint256 constant MIN_BUY_T1 = 0.98 * 1e36;
    uint256 constant MAX_SELL_T1 = 1.02 * 1e36;

    function handler_setPrices(uint256 buyT1, uint256 sellT1) public {
        uint256 crossPrice = lidoARM.crossPrice();

        // Bound prices
        buyT1 = _bound(buyT1, MIN_BUY_T1, crossPrice - 1);
        sellT1 = _bound(sellT1, crossPrice, MAX_SELL_T1);

        // Prank owner
        vm.prank(lidoARM.owner());

        // Set prices
        lidoARM.setPrices(buyT1, sellT1);
    }

    function handler_setCrossPrice(uint256 newCrossPrice) public {
        uint256 priceScale = lidoARM.PRICE_SCALE();

        // Bound new cross price
        uint256 sell = priceScale ** 2 / lidoARM.traderate0();
        uint256 buy = lidoARM.traderate1();
        newCrossPrice = _bound(
            newCrossPrice, max(priceScale - lidoARM.MAX_CROSS_PRICE_DEVIATION(), buy) + 1, min(priceScale, sell)
        );

        // Prank owner
        vm.prank(lidoARM.owner());

        // Set cross price
        lidoARM.setCrossPrice(newCrossPrice);
    }

    function handler_setFee(uint256 performanceFee) public {
        performanceFee = _bound(performanceFee, MIN_FEES, MAX_FEES);

        // Cache accrued fees before setting new fee
        uint256 accumulatedFees = lidoARM.feesAccrued();

        // Prank owner
        vm.prank(lidoARM.owner());

        // Set fees
        lidoARM.setFee(performanceFee);

        // Update ghost
        sum_weth_fees += accumulatedFees;
    }

    function handler_collectFees() public {
        // Prank owner
        vm.prank(lidoARM.owner());

        // Collect fees
        uint256 collectedFees = lidoARM.collectFees();

        // Update ghost
        sum_weth_fees += collectedFees;
    }

    function handler_totalAsset() public view returns (uint256) {
        return lidoARM.totalAssets();
    }

    function handler_feeAccrued() public view returns (uint256) {
        return lidoARM.feesAccrued();
    }

    function handler_lastAvailableAsset() public view returns (int128) {
        return lidoARM.lastAvailableAssets();
    }

    ////////////////////////////////////////////////////
    /// --- DONATION
    ////////////////////////////////////////////////////
    uint256 constant DONATION_PROBABILITY = 10;
    uint256 constant DONATION_THRESHOLD = 1e20;

    function handler_donate(bool stETH, uint64 amount, uint256 probability) public {
        // Reduce probability to 10%
        vm.assume(probability % DONATION_PROBABILITY == 0 && lidoARM.totalSupply() > DONATION_THRESHOLD);

        IERC20 token = stETH ? IERC20(address(steth)) : IERC20(address(weth));

        deal(address(token), address(this), amount);

        token.transfer(address(lidoARM), amount);

        // Update ghost
        stETH ? sum_steth_donated += amount : sum_weth_donated += amount;
    }

    ////////////////////////////////////////////////////
    /// --- HELPERS
    ////////////////////////////////////////////////////
    uint256 constant SHARES_UP_ONLY__ERROR_TOLERANCE = 1e6;

    function finalizeLidoClaims() public {
        if (lidoWithdrawRequests.length == 0) return;

        // Prank Owner
        vm.prank(lidoARM.owner());
        lidoARM.claimLidoWithdrawals(lidoWithdrawRequests, new uint256[](0));

        require(lidoARM.lidoWithdrawalQueueAmount() == 0, "FINALIZE_FAILED");
    }

    function sweepAllStETH() public {
        deal(address(weth), address(this), 1e30);
        weth.approve(address(lidoARM), type(uint256).max);
        lidoARM.swapTokensForExactTokens(
            weth, steth, steth.balanceOf(address(lidoARM)), type(uint256).max, address(this)
        );
        require(steth.balanceOf(address(lidoARM)) == 0, "SWEEP_FAILED");
    }

    function finalizeUserClaims() public {
        // Timejump to request deadline
        skip(lidoARM.claimDelay());

        // Loop on all LPs
        for (uint256 i; i < lps.length; i++) {
            address user = lps[i];
            uint256 requestCount = requests[user].length;

            // Prank LP
            vm.startPrank(user);

            // Loop on all requests && Claim redeem
            for (uint256 j; j < requestCount; j++) {
                lidoARM.claimRedeem(requests[user][j]);
            }

            vm.stopPrank();
        }

        // No need to jump back to current time, as we are done with the test
    }

    function ensureSharesAreUpOnly(uint256 initialBalance) public view returns (bool) {
        for (uint256 i; i < lps.length; i++) {
            address user = lps[i];
            uint256 shares = lidoARM.balanceOf(user);
            uint256 sum = weth.balanceOf(user) + lidoARM.previewRedeem(shares);
            if (!gte(sum * (1e18 + SHARES_UP_ONLY__ERROR_TOLERANCE) / 1e18, initialBalance)) {
                return false;
            }
        }
        return true;
    }
}
