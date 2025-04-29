// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Setup} from "./Setup.sol";
import {Helpers} from "./Helpers.sol";

// Interfaces
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

abstract contract Properties is Setup, Helpers {
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                           ✦✦✦ SWAP PROPERTIES ✦✦✦                            ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] Invariant A: ws balance == ∑deposit + ∑swapIn + ∑redeem + ∑inMarket + ∑donated - ∑swapOut - ∑feesCollected
    // [x] Invariant B: steth balance >= ∑stethIn + ∑stethDonated - ∑stethOut - ∑stethRedeem
    // [x] Invariant C: when swap => AmountIn  == amounts[0]
    // [x] Invariant D: when swap => AmountOut == amounts[1]

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                            ✦✦✦ LP PROPERTIES ✦✦✦                             ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] Invariant A: ∑shares > 0 due to initial deposit
    // [x] Invariant B: totalShares == ∑userShares + deadShares
    // [x] Invariant C: previewRedeem(∑shares) == totalAssets
    // [x] Invariant D: previewRedeem(shares) == (, uint256 assets) *
    // [x] Invariant E: previewDeposit(amount) == uint256 shares *
    // [x] Invariant F: nextWithdrawalIndex == requestRedeem call count *
    // [x] Invariant G: withdrawsQueued == ∑requestRedeem.amount
    // [x] Invariant H: withdrawsQueued > withdrawsClaimed
    // [x] Invariant I: withdrawsQueued == ∑request.assets
    // [x] Invariant J: withdrawsClaimed == ∑claimRedeem.amount
    // [x] Invariant K: ∀ requestId, request.queued >= request.assets
    // [x] Invariant L: ∑feesCollected == feeCollector.balance
    // * invariants tested directly in the handlers.

    // --- Inflow
    uint256 public sum_ws_deposit;
    uint256 public sum_ws_swapIn;
    uint256 public sum_os_swapIn;
    uint256 public sum_ws_donated;
    uint256 public sum_os_donated;
    uint256 public sum_ws_arm_claimed;

    // --- Outflow
    uint256 public sum_ws_redeem;
    uint256 public sum_os_redeem;
    uint256 public sum_ws_user_claimed;
    uint256 public sum_ws_swapOut;
    uint256 public sum_os_swapOut;
    uint256 public sum_feesCollected;

    function property_swap_A() public view returns (bool) {
        IERC4626 activeMarket = IERC4626(originARM.activeMarket());
        uint256 inflow = MIN_TOTAL_SUPPLY + sum_ws_deposit + sum_ws_swapIn + sum_ws_donated + sum_ws_arm_claimed;
        uint256 outflow = sum_ws_swapOut + sum_feesCollected + sum_ws_user_claimed;
        uint256 wsInMarket = address(activeMarket) == address(0) ? 0 : activeMarket.maxWithdraw(address(originARM));
        return ws.balanceOf(address(originARM)) + wsInMarket == inflow - outflow;
    }

    function property_swap_B() public view returns (bool) {
        uint256 inflow = sum_os_swapIn + sum_os_donated;
        uint256 outflow = sum_os_redeem + sum_os_swapOut;
        return os.balanceOf(address(originARM)) == inflow - outflow;
    }

    function property_lp_A() public view returns (bool) {
        return originARM.totalSupply() > 0;
    }

    function property_lp_B() public view returns (bool) {
        return originARM.totalSupply() == sumOfShares();
    }

    function property_lp_C() public view returns (bool) {
        return originARM.previewRedeem(originARM.totalSupply()) == originARM.totalAssets();
    }

    function property_lp_G() public view returns (bool) {
        return originARM.withdrawsQueued() == sum_ws_redeem;
    }

    function property_lp_H() public view returns (bool) {
        return originARM.withdrawsQueued() >= originARM.withdrawsClaimed();
    }

    function property_lp_I() public view returns (bool) {
        return originARM.withdrawsQueued() == sumOfRequestRedeemAmount();
    }

    function property_lp_J() public view returns (bool) {
        return originARM.withdrawsClaimed() == sum_ws_user_claimed;
    }

    function property_lp_K() public view returns (bool) {
        uint256 len = originARM.nextWithdrawalIndex();
        for (uint256 i; i < len; i++) {
            (,,, uint128 amount, uint128 queued) = originARM.withdrawalRequests(i);
            if (queued < amount) {
                return false;
            }
        }
        return true;
    }

    function property_lp_L() public view returns (bool) {
        return ws.balanceOf(feeCollector) == sum_feesCollected;
    }

    function sumOfShares() public view returns (uint256 usersShares) {
        for (uint256 i; i < lps.length; i++) {
            usersShares += originARM.balanceOf(lps[i]);
        }
        usersShares += MIN_TOTAL_SUPPLY;
    }

    function sumOfRequestRedeemAmount() public view returns (uint256 sum) {
        uint256 len = originARM.nextWithdrawalIndex();
        for (uint256 i; i < len; i++) {
            (,,, uint128 amount,) = originARM.withdrawalRequests(i);
            sum += amount;
        }
    }
}
