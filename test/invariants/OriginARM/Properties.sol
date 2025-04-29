// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Setup} from "./Setup.sol";
import {Helpers} from "./Helpers.sol";
import {console} from "forge-std/console.sol";
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
    // [ ] Invariant A: ∑shares > 0 due to initial deposit
    // [ ] Invariant B: totalShares == ∑userShares + deadShares
    // [ ] Invariant C: previewRedeem(∑shares) == totalAssets
    // [ ] Invariant D: previewRedeem(shares) == (, uint256 assets) = previewRedeem(shares)
    // [ ] Invariant E: previewDeposit(amount) == uint256 shares = previewDeposit(amount)
    // [ ] Invariant F: nextWithdrawalIndex == requestRedeem call count
    // [ ] Invariant G: withdrawsQueued == ∑requestRedeem.amount
    // [ ] Invariant H: withdrawsQueued > withdrawsClaimed
    // [ ] Invariant I: withdrawsQueued == ∑request.assets
    // [ ] Invariant J: withdrawsClaimed == ∑claimRedeem.amount
    // [ ] Invariant K: ∀ requestId, request.queued >= request.assets
    // [ ] Invariant M: ∑feesCollected == feeCollector.balance

    // --- Inflow
    uint256 public sum_ws_deposit;
    uint256 public sum_ws_swapIn;
    uint256 public sum_os_swapIn;
    uint256 public sum_ws_donated;
    uint256 public sum_os_donated;
    uint256 public sum_ws_claimed;

    // --- Outflow
    uint256 public sum_ws_redeem;
    uint256 public sum_os_redeem;
    uint256 public sum_ws_swapOut;
    uint256 public sum_os_swapOut;
    uint256 public sum_feesCollected;

    function property_swap_A() public view returns (bool) {
        IERC4626 activeMarket = IERC4626(originARM.activeMarket());
        uint256 inflow = MIN_TOTAL_SUPPLY + sum_ws_deposit + sum_ws_swapIn + sum_ws_donated + sum_ws_claimed;
        uint256 outflow = sum_ws_redeem + sum_ws_swapOut + sum_feesCollected;
        uint256 wsInMarket = address(activeMarket) == address(0) ? 0 : activeMarket.maxWithdraw(address(originARM));
        return ws.balanceOf(address(originARM)) + wsInMarket == inflow - outflow;
    }

    function property_swap_B() public view returns (bool) {
        uint256 inflow = sum_os_swapIn + sum_os_donated;
        uint256 outflow = sum_os_redeem + sum_os_swapOut;
        return os.balanceOf(address(originARM)) == inflow - outflow;
    }
}
