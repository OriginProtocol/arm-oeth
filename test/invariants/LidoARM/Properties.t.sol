// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {TargetFunction} from "./TargetFunction.t.sol";

abstract contract Properties is TargetFunction {
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                            ✦✦✦ LP PROPERTIES ✦✦✦                             ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] Invariant A: totalSupply > 0 (dead shares guarantee)
    // [x] Invariant B: totalSupply == ∑balanceOf(lps) + balanceOf(ARM) + balanceOf(DEAD)
    // [x] Invariant C: previewRedeem(totalSupply) == totalAssets
    // [x] Invariant D: reservedWithdrawLiquidity == ∑unclaimed request.assets
    // [x] Invariant E: withdrawsQueuedShares >= withdrawsClaimedShares
    // [x] Invariant F: withdrawsQueuedShares == ∑request.shares
    // [x] Invariant G: withdrawsClaimedShares == ∑claimed request.shares
    // [x] Invariant H: ARM escrowed shares == withdrawsQueuedShares - withdrawsClaimedShares
    // [x] Invariant I: ∑feesCollected == feeCollector.balanceOf(WETH)
    // [x] Invariant Q: ∀ LP, convertToAssets(shares) + claimed + transferOut >= deposited + transferIn
    //                   (tolerance = 100 wei base + depositCount × shareValue, since each deposit rounds
    //                    shares down by up to one share's worth of assets in favour of the vault)
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                       ✦✦✦ WITHDRAWAL INDEX PROPERTIES ✦✦✦                    ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] Invariant J: nextWithdrawalIndex == ghost_requestCounter
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                    ✦✦✦ LIQUIDITY MANAGEMENT PROPERTIES ✦✦✦                   ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] Invariant K: address(ARM).balance == 0
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                        ✦✦✦ FEE ACCOUNTING PROPERTIES ✦✦✦                     ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] Invariant L: feesAccrued + ∑feesCollected == ∑feesAccrued (exact match)
    // [x] Invariant M: feesAccrued + ∑feesCollected <= ∑buysideOut × maxSpread × maxFee
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                     ✦✦✦ BALANCE CONSERVATION PROPERTIES ✦✦✦                  ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] Invariant N: WETH balance + market value >= MIN_TOTAL_SUPPLY
    //                   + ∑deposit + ∑swapIn + ∑baseRedeemClaimed + ∑donated
    //                   - ∑swapOut - ∑userClaimed - ∑feesCollected
    //                   (100 wei tolerance — optimization found worst-case 27 wei / 250k txs)
    // [x] Invariant O: stETH balance == ∑swapIn + ∑donated + ∑rebased
    //                                    - ∑swapOut - ∑baseRedeemRequested
    // [x] Invariant P: wstETH balance == ∑swapIn + ∑donated
    //                                     - ∑swapOut - ∑baseRedeemRequested
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                       ✦✦✦ SHARE PRICE PROPERTIES ✦✦✦                         ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] Invariant R: share price never decreases (enforced via modifier, except setCrossPrice)
    //                   (2 wei tolerance — optimization found worst-case 0 wei / 250k txs)
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                                   ✦✦✦  ✦✦✦                                   ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝

    // 1. totalSupply > 0 (dead shares guarantee)
    function property_lp_A() public view returns (bool) {
        return lidoARM.totalSupply() > 0;
    }

    // 2. totalSupply == sum of all holder balances
    function property_lp_B() public view returns (bool) {
        return lidoARM.totalSupply() == sumOfUserShares();
    }

    // 3. previewRedeem(totalSupply) == totalAssets
    function property_lp_C() public view returns (bool) {
        return lidoARM.previewRedeem(lidoARM.totalSupply()) == lidoARM.totalAssets();
    }

    // 4. reservedWithdrawLiquidity == sum of unclaimed request assets
    function property_lp_D() public view returns (bool) {
        return lidoARM.reservedWithdrawLiquidity() == sumOfUnclaimedRequestAssets();
    }

    // 5. withdrawsQueuedShares >= withdrawsClaimedShares
    function property_lp_E() public view returns (bool) {
        return lidoARM.withdrawsQueuedShares() >= lidoARM.withdrawsClaimedShares();
    }

    // 6. withdrawsQueuedShares == ghost sum of requested shares
    function property_lp_F() public view returns (bool) {
        return lidoARM.withdrawsQueuedShares() == sum_shares_requested;
    }

    // 7. withdrawsClaimedShares == ghost sum of claimed shares
    function property_lp_G() public view returns (bool) {
        return lidoARM.withdrawsClaimedShares() == sum_shares_claimed;
    }

    // 8. ARM escrowed shares == queued - claimed
    function property_lp_H() public view returns (bool) {
        return lidoARM.balanceOf(address(lidoARM)) == lidoARM.withdrawsQueuedShares() - lidoARM.withdrawsClaimedShares();
    }

    // 9. Collected fees == feeCollector WETH balance
    function property_lp_I() public view returns (bool) {
        return weth.balanceOf(lidoARM.feeCollector()) == sum_weth_feesCollected;
    }

    // 10. No LP suffers a loss (accounting for deposits, claims, transfers, and pending requests)
    // Skipped after setCrossPrice which can legitimately reduce share value.
    function property_lp_noLoss() public view returns (bool) {
        if (ghost_crossPriceChanged) return true;
        address[6] memory allLps = [alice, bobby, carol, david, elise, frank];
        for (uint256 i; i < allLps.length; i++) {
            address lp = allLps[i];
            uint256 currentValue = lidoARM.convertToAssets(lidoARM.balanceOf(lp));
            uint256 pendingValue = sumOfUserPendingAssets(lp);
            uint256 totalOut = currentValue + pendingValue + ghost_userClaimed[lp] + ghost_userTransferOutValue[lp];
            uint256 totalIn = ghost_userDeposited[lp] + ghost_userTransferInValue[lp];
            if (totalOut + lpLossTolerance(lp) < totalIn) return false;
        }
        return true;
    }

    /// @notice Per-LP allowed rounding loss in wei.
    /// @dev Each ERC4626-style deposit mints `floor(assets * totalSupply / netAssets)` shares, so the
    ///      depositor forfeits up to the value of one share (rounded in favour of the vault). That loss is
    ///      unavoidable and grows linearly with the number of deposits, so the tolerance must scale with the
    ///      deposit count times the current share value, not stay a fixed constant. A 100 wei base absorbs
    ///      the redeem/transfer rounding that does not scale with deposits.
    function lpLossTolerance(address lp) internal view returns (uint256) {
        uint256 totalSupply = lidoARM.totalSupply();
        // Value of one share, rounded up: the maximum assets a single deposit can round away.
        uint256 shareValueCeil = (lidoARM.totalAssets() + totalSupply - 1) / totalSupply;
        return 100 + ghost_userDepositCount[lp] * shareValueCeil;
    }

    /// @notice Returns the max rounding loss (over its per-LP tolerance) in wei across all LPs.
    function maxLpLoss() public view returns (int256 maxLoss) {
        if (ghost_crossPriceChanged) return 0;
        address[6] memory allLps = [alice, bobby, carol, david, elise, frank];
        for (uint256 i; i < allLps.length; i++) {
            address lp = allLps[i];
            uint256 currentValue = lidoARM.convertToAssets(lidoARM.balanceOf(lp));
            uint256 pendingValue = sumOfUserPendingAssets(lp);
            uint256 totalOut = currentValue + pendingValue + ghost_userClaimed[lp] + ghost_userTransferOutValue[lp];
            uint256 totalIn = ghost_userDeposited[lp] + ghost_userTransferInValue[lp];
            uint256 tolerance = lpLossTolerance(lp);
            // Only surface loss that exceeds the unavoidable per-deposit rounding allowance.
            if (totalIn > totalOut + tolerance) {
                int256 loss = int256(totalIn) - int256(totalOut) - int256(tolerance);
                if (loss > maxLoss) maxLoss = loss;
            }
        }
    }

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                       ✦✦✦ WITHDRAWAL INDEX PROPERTIES ✦✦✦                    ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝

    // 10. nextWithdrawalIndex == ghost request counter
    function property_wi_A() public view returns (bool) {
        return lidoARM.nextWithdrawalIndex() == ghost_requestCounter;
    }

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                    ✦✦✦ LIQUIDITY MANAGEMENT PROPERTIES ✦✦✦                   ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝

    // 11. ARM should not hold native ETH
    function property_llm_A() public view returns (bool) {
        return address(lidoARM).balance == 0;
    }

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                        ✦✦✦ FEE ACCOUNTING PROPERTIES ✦✦✦                     ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝

    // 12. Exact match: feesAccrued + collected == total ever accrued
    function property_fee_A() public view returns (bool) {
        return lidoARM.feesAccrued() + sum_fees_collected == sum_fees_accrued;
    }

    // 13. Upper bound: fees cannot exceed max spread * max fee on total buy-side volume
    function property_fee_B() public view returns (bool) {
        // maxSpread = (PRICE_SCALE - MINIMUM_BUY_PRICE) / MINIMUM_BUY_PRICE
        // maxFee = FEE_SCALE / 2
        // round up: conservative upper bound
        uint256 maxFees = Math.mulDiv(
            sum_weth_buyside_out,
            (PRICE_SCALE - MINIMUM_BUY_PRICE) * (FEE_SCALE / 2),
            MINIMUM_BUY_PRICE * FEE_SCALE,
            Math.Rounding.Ceil
        );
        return lidoARM.feesAccrued() + sum_fees_collected <= maxFees;
    }

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                     ✦✦✦ BALANCE CONSERVATION PROPERTIES ✦✦✦                  ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝

    // 14. WETH balance + market deposits >= MIN_TOTAL_SUPPLY + inflows - outflows
    function property_bal_weth() public view returns (bool) {
        uint256 armWeth = weth.balanceOf(address(lidoARM));

        // Include WETH in both markets. Use convertToAssets (economic value), not maxWithdraw
        // (which is capped by utilization and would break conservation accounting).
        uint256 wethInMarkets = IERC4626(address(mockERC4626Market_A))
            .convertToAssets(IERC4626(address(mockERC4626Market_A)).balanceOf(address(lidoARM)))
        + IERC4626(address(mockERC4626Market_B))
            .convertToAssets(IERC4626(address(mockERC4626Market_B)).balanceOf(address(lidoARM)));

        uint256 inflows =
            MIN_TOTAL_SUPPLY + sum_weth_deposit + sum_weth_swapIn + sum_weth_baseRedeemClaimed + sum_weth_donated;
        uint256 outflows = sum_weth_swapOut + sum_weth_userClaimed + sum_weth_feesCollected;

        // Rewrite as: lhs + outflows + tolerance >= inflows (avoids underflow)
        // Market yield can make lhs > inflows - outflows (ARM gained value from yield).
        // ERC4626 rounding can lose a few wei per cycle.
        // Optimization mode found worst-case of 27 wei over ~250k txs.
        return armWeth + wethInMarkets + outflows + 100 >= inflows;
    }

    // 15. stETH balance == inflows - outflows
    function property_bal_steth() public view returns (bool) {
        uint256 armSteth = steth.balanceOf(address(lidoARM));
        uint256 inflows = sum_steth_swapIn + sum_steth_donated + sum_steth_rebased;
        uint256 outflows = sum_steth_swapOut + sum_steth_baseRedeemRequested;

        if (inflows >= outflows) {
            return armSteth == inflows - outflows;
        } else {
            return armSteth == 0 && outflows - inflows <= 1;
        }
    }

    // 16. wstETH balance == inflows - outflows
    function property_bal_wsteth() public view returns (bool) {
        uint256 armWsteth = wsteth.balanceOf(address(lidoARM));
        uint256 inflows = sum_wsteth_swapIn + sum_wsteth_donated;
        uint256 outflows = sum_wsteth_swapOut + sum_wsteth_baseRedeemRequested;

        return armWsteth == inflows - outflows;
    }

    ////////////////////////////////////////////////////
    /// --- OPTIMIZATION METRICS
    ////////////////////////////////////////////////////

    /// @notice Max WETH rounding loss from market deposit/withdraw cycles.
    function maxWethBalanceDrift() public view returns (int256) {
        uint256 armWeth = weth.balanceOf(address(lidoARM));
        uint256 wethInMarkets = IERC4626(address(mockERC4626Market_A))
            .convertToAssets(IERC4626(address(mockERC4626Market_A)).balanceOf(address(lidoARM)))
        + IERC4626(address(mockERC4626Market_B))
            .convertToAssets(IERC4626(address(mockERC4626Market_B)).balanceOf(address(lidoARM)));

        uint256 inflows =
            MIN_TOTAL_SUPPLY + sum_weth_deposit + sum_weth_swapIn + sum_weth_baseRedeemClaimed + sum_weth_donated;
        uint256 outflows = sum_weth_swapOut + sum_weth_userClaimed + sum_weth_feesCollected;

        uint256 lhs = armWeth + wethInMarkets + outflows;
        // Return how much inflows exceeds lhs (positive = loss)
        if (inflows > lhs) return int256(inflows - lhs);
        return 0;
    }

    /// @notice Max share price decrease in a single call (from modifier).
    ///         Tracked via ghost_lastSharePrice vs current.
    function sharePriceDrop() public view returns (int256) {
        uint256 current = lidoARM.totalAssets() * 1e18 / lidoARM.totalSupply();
        if (ghost_lastSharePrice > current) {
            return int256(ghost_lastSharePrice - current);
        }
        return 0;
    }
}
