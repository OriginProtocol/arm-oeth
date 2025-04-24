// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Test imports
import {Utils} from "./Utils.sol";
import {Setup} from "./Setup.sol";

abstract contract Properties is Setup, Utils {
    ////////////////////////////////////////////////////
    /// --- GHOSTS
    ////////////////////////////////////////////////////
    uint256 sum_weth_fees;
    uint256 sum_weth_swap_in;
    uint256 sum_weth_swap_out;
    uint256 sum_weth_deposit;
    uint256 sum_weth_request;
    uint256 sum_weth_withdraw;
    uint256 sum_weth_donated;
    uint256 sum_weth_lido_redeem;
    uint256 sum_steth_lido_requested;
    uint256 sum_steth_swap_out;
    uint256 sum_steth_swap_in;
    uint256 sum_steth_donated;
    uint256 ghost_requestCounter;
    bool ghost_swap_C = true;
    bool ghost_swap_D = true;
    bool ghost_lp_D = true;
    bool ghost_lp_E = true;
    bool ghost_lp_K = true;

    ////////////////////////////////////////////////////
    /// --- PROPERTIES
    ////////////////////////////////////////////////////

    // --- Swap properties ---
    // Invariant A: weth balance == ∑deposit + ∑wethIn + ∑wethRedeem + ∑wethDonated - ∑withdraw - ∑wethOut - ∑feesCollected
    // Invariant B: steth balance >= ∑stethIn + ∑stethDonated - ∑stethOut - ∑stethRedeem
    // Invariant C: when swap => AmountIn  == amounts[0]
    // Invariant D: when swap => AmountOut == amounts[1]

    // --- Liquidity Provider properties ---
    // Invariant A: ∑shares > 0 due to initial deposit
    // Invariant B: totalShares == ∑userShares + deadShares
    // Invariant C: previewRedeem(∑shares) == totalAssets
    // Invariant D: previewRedeem(shares) == (, uint256 assets) = previewRedeem(shares)
    // Invariant E: previewDeposit(amount) == uint256 shares = previewDeposit(amount)
    // Invariant F: nextWithdrawalIndex == requestRedeem call count
    // Invariant G: withdrawsQueued == ∑requestRedeem.amount
    // Invariant H: withdrawsQueued > withdrawsClaimed
    // Invariant I: withdrawsQueued == ∑request.assets
    // Invariant J: withdrawsClaimed == ∑claimRedeem.amount
    // Invariant K: ∀ requestId, request.queued >= request.assets
    // Invariant M: ∑feesCollected == feeCollector.balance

    // --- Lido Liquidity Management properties ---
    // Invariant A: lidoWithdrawalQueueAmount == ∑lidoRequestRedeem.assets
    // Invariant B: address(arm).balance == 0

    ////////////////////////////////////////////////////
    /// --- SWAPS
    ////////////////////////////////////////////////////
    function property_swap_A() public view returns (bool) {
        uint256 inflows = sum_weth_deposit + sum_weth_swap_in + sum_weth_lido_redeem + sum_weth_donated;
        uint256 outflows = sum_weth_swap_out + sum_weth_withdraw + sum_weth_fees;

        return eq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + inflows - outflows);
    }

    function property_swap_B() public view returns (bool) {
        uint256 inflows = sum_steth_donated + sum_steth_swap_in;
        uint256 outflows = sum_steth_swap_out + sum_steth_lido_requested;

        return eq(steth.balanceOf(address(lidoARM)), inflows - outflows);
    }

    function property_swap_C() public view returns (bool) {
        return ghost_swap_C;
    }

    function property_swap_D() public view returns (bool) {
        return ghost_swap_D;
    }

    ////////////////////////////////////////////////////
    /// --- LIQUIDITY PROVIDERS
    ////////////////////////////////////////////////////
    function property_lp_A() public view returns (bool) {
        return gt(lidoARM.totalSupply(), 0);
    }

    function property_lp_B() public view returns (bool) {
        return eq(lidoARM.totalSupply(), sumOfUserShares());
    }

    function property_lp_C() public view returns (bool) {
        return eq(lidoARM.previewRedeem(sumOfUserShares()), lidoARM.totalAssets());
    }

    function property_lp_D() public view returns (bool) {
        return ghost_lp_D;
    }

    function property_lp_E() public view returns (bool) {
        return ghost_lp_E;
    }

    function property_lp_F() public view returns (bool) {
        return eq(lidoARM.nextWithdrawalIndex(), ghost_requestCounter);
    }

    function property_lp_G() public view returns (bool) {
        return eq(lidoARM.withdrawsQueued(), sum_weth_request);
    }

    function property_lp_H() public view returns (bool) {
        return gte(lidoARM.withdrawsQueued(), lidoARM.withdrawsClaimed());
    }

    function property_lp_I() public view returns (bool) {
        uint256 sum;
        uint256 nextWithdrawalIndex = lidoARM.nextWithdrawalIndex();
        for (uint256 i; i < nextWithdrawalIndex; i++) {
            (,,, uint128 assets,) = lidoARM.withdrawalRequests(i);
            sum += assets;
        }

        return eq(lidoARM.withdrawsQueued(), sum);
    }

    function property_lp_invariant_J() public view returns (bool) {
        return eq(lidoARM.withdrawsClaimed(), sum_weth_withdraw);
    }

    function property_lp_invariant_K() public view returns (bool) {
        uint256 nextWithdrawalIndex = lidoARM.nextWithdrawalIndex();
        for (uint256 i; i < nextWithdrawalIndex; i++) {
            (,,, uint128 assets, uint128 queued) = lidoARM.withdrawalRequests(i);
            if (queued < assets) return false;
        }

        return true;
    }

    function property_lp_invariant_M() public view returns (bool) {
        address feeCollector = lidoARM.feeCollector();
        return eq(weth.balanceOf(feeCollector), sum_weth_fees);
    }

    ////////////////////////////////////////////////////
    /// --- LIDO LIQUIDITY MANAGMENT
    ////////////////////////////////////////////////////
    function property_llm_A() public view returns (bool) {
        return eq(lidoARM.lidoWithdrawalQueueAmount(), sum_steth_lido_requested - sum_weth_lido_redeem);
    }

    function property_llm_B() public view returns (bool) {
        return eq(address(lidoARM).balance, 0);
    }

    ////////////////////////////////////////////////////
    /// --- HELPERS
    ////////////////////////////////////////////////////
    function estimateAmountIn(IERC20 tokenOut, uint256 amountOut) public view returns (uint256) {
        return (amountOut * lidoARM.PRICE_SCALE()) / price(tokenOut == weth ? steth : weth) + 3;
    }

    function estimateAmountOut(IERC20 tokenIn, uint256 amountIn) public view returns (uint256) {
        return (amountIn * price(tokenIn)) / lidoARM.PRICE_SCALE();
    }

    function price(IERC20 token) public view returns (uint256) {
        return token == lidoARM.token0() ? lidoARM.traderate0() : lidoARM.traderate1();
    }

    function sumOfUserShares() public view returns (uint256) {
        uint256 sum_shares;

        for (uint256 i; i < lps.length; i++) {
            sum_shares += lidoARM.balanceOf(lps[i]);
        }

        sum_shares += lidoARM.balanceOf(address(0xdEaD));

        return sum_shares;
    }
}
