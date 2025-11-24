// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {console} from "forge-std/console.sol";

// Test imports
import {TargetFunctions} from "./TargetFunctions.sol";

// Helpers
import {Math} from "./helpers/Math.sol";

// Interfaces
import {UserCooldown} from "contracts/Interfaces.sol";

/// @title Properties
/// @notice Abstract contract defining invariant properties for formal verification and fuzzing.
/// @dev    This contract contains pure property functions that express system invariants:
///         - Properties must be implemented as view/pure functions returning bool
///         - Each property should represent a mathematical invariant of the system
///         - Properties should be stateless and deterministic
///         - Property names should clearly indicate what invariant they check
///         Usage: Properties are called by fuzzing contracts to validate system state
abstract contract Properties is TargetFunctions {
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                           ✦✦✦ SWAP PROPERTIES ✦✦✦                            ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [ ] Invariant A: USDe  balance == ∑swapIn - ∑swapOut
    //                                   + ∑userDeposit - ∑userWithdraw
    //                                   + ∑marketWithdraw - ∑marketDeposit
    //                                   + ∑baseRedeem - ∑feesCollected
    // [ ] Invariant B: sUSDe balance == (∑swapIn - ∑swapOut) - ∑baseRedeem
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                            ✦✦✦ LP PROPERTIES ✦✦✦                             ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] Invariant C: ∑shares > 0 due to initial deposit
    // [x] Invariant D: totalShares == ∑userShares + deadShares
    // [x] Invariant E: previewRedeem(∑shares) == totalAssets
    // [x] Invariant F: withdrawsQueued == ∑requestRedeem.amount
    // [x] Invariant G: withdrawsQueued > withdrawsClaimed
    // [x] Invariant H: withdrawsQueued == ∑request.assets
    // [x] Invariant I: withdrawsClaimed == ∑claimRedeem.amount
    // [x] Invariant J: ∀ requestId, request.queued >= request.assets
    // [x] Invariant K: ∑feesCollected == feeCollector.balance
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                         ✦✦✦ LIQUIDITY MANAGEMENT ✦✦✦                         ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] Invariant L: liquidityAmountInCooldown == ∑unstaker.underlyingAmount
    // [x] Invariant M: nextUnstakerIndex < MAX_UNSTAKERS
    // [x] Invariant N: ∀ unstaker, usde.balanceOf(unstaker) == 0 && susde.balanceOf(unstaker) == 0
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                              ✦✦✦ AFTER ALL ✦✦✦                               ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] USDe in ARM < 1 ether
    // [x] sUSDe in ARM == 0
    // [x] Morpho shares in ARM == 0
    // [x] ARM total assets < 1 ether
    // [x] ∀ user, usde.balanceOf(user) >= totalMinted - 1e1
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                                   ✦✦✦  ✦✦✦                                   ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                           ✦✦✦ SWAP PROPERTIES ✦✦✦                            ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    function propertyA() public view returns (bool) {
        uint256 usdeBalance = usde.balanceOf(address(arm));
        uint256 inflow = 1e12 + sumUSDeSwapIn + sumUSDeUserDeposit + sumUSDeMarketWithdraw + sumUSDeBaseRedeem;
        uint256 outflow = sumUSDeSwapOut + sumUSDeUserRedeem + sumUSDeMarketDeposit + sumUSDeFeesCollected;
        // console.log(">>> Property A:");
        // console.log("    - USDe balance:         %18e", usdeBalance);
        // console.log("    - Inflow breakdown:");
        // console.log("        o Initial buffer:   %18e", uint256(1e12));
        // console.log("        o Swap In:          %18e", sumUSDeSwapIn);
        // console.log("        o User Deposit:     %18e", sumUSDeUserDeposit);
        // console.log("        o Market Withdraw:  %18e", sumUSDeMarketWithdraw);
        // console.log("        o Base Redeem:      %18e", sumUSDeBaseRedeem);
        // console.log("    - USDe inflow sum:      %18e", inflow);
        // console.log("    - Outflow breakdown:");
        // console.log("        o Swap Out:         %18e", sumUSDeSwapOut);
        // console.log("        o User Redeem:      %18e", sumUSDeUserRedeem);
        // console.log("        o Market Deposit:   %18e", sumUSDeMarketDeposit);
        // console.log("        o Fees Collected:   %18e", sumUSDeFeesCollected);
        // console.log("    - USDe outflow sum:     %18e", outflow);
        // console.log("    - Diff:                 %18e", Math.absDiff(inflow, outflow));
        return Math.eq(usdeBalance, Math.absDiff(inflow, outflow));
    }

    function propertyB() public view returns (bool) {
        uint256 susdeBalance = susde.balanceOf(address(arm));
        uint256 inflow = sumSUSDeSwapIn;
        uint256 outflow = sumSUSDeSwapOut + sumSUSDeBaseRedeem;
        // console.log(">>> Property B:");
        // console.log("    - sUSDe balance:        %18e", susdeBalance);
        // console.log("    - Inflow breakdown:");
        // console.log("        o Swap In:          %18e", sumSUSDeSwapIn);
        // console.log("    - sUSDe inflow sum:     %18e", inflow);
        // console.log("    - Outflow breakdown:");
        // console.log("        o Swap Out:         %18e", sumSUSDeSwapOut);
        // console.log("        o Base Redeem:      %18e", sumSUSDeBaseRedeem);
        // console.log("    - sUSDe outflow sum:    %18e", outflow);
        // console.log("    - Diff:                 %18e", Math.absDiff(inflow, outflow));
        return Math.eq(susdeBalance, Math.absDiff(inflow, outflow));
    }

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                            ✦✦✦ LP PROPERTIES ✦✦✦                             ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    function propertyC() public view returns (bool) {
        return Math.gt(arm.totalSupply(), 0);
    }

    function propertyD() public view returns (bool) {
        uint256 totalUserShares = 0;
        for (uint256 i = 0; i < MAKERS_COUNT; i++) {
            totalUserShares += arm.balanceOf(makers[i]);
        }
        uint256 deadShares = 1e12;
        return Math.eq(arm.totalSupply(), totalUserShares + deadShares);
    }

    function propertyE() public view returns (bool) {
        return Math.eq(arm.previewRedeem(arm.totalSupply()), arm.totalAssets());
    }

    function propertyF() public view returns (bool) {
        return Math.eq(arm.withdrawsQueued(), sumUSDeUserRequest);
    }

    function propertyG() public view returns (bool) {
        return Math.gte(arm.withdrawsQueued(), arm.withdrawsClaimed());
    }

    function propertyH() public view returns (bool) {
        uint256 sum = 0;
        uint256 len = arm.nextWithdrawalIndex();
        for (uint256 i; i < len; i++) {
            (,,, uint128 amount,) = arm.withdrawalRequests(i);
            sum += amount;
        }
        return Math.eq(arm.withdrawsQueued(), sum);
    }

    function propertyI() public view returns (bool) {
        return Math.eq(arm.withdrawsClaimed(), sumUSDeUserRedeem);
    }

    function propertyJ() public view returns (bool) {
        uint256 len = arm.nextWithdrawalIndex();
        for (uint256 i; i < len; i++) {
            (,,, uint128 amount, uint128 queued) = arm.withdrawalRequests(i);
            if (queued < amount) {
                return false;
            }
        }
        return true;
    }

    function propertyK() public view returns (bool) {
        uint256 feeCollectorBalance = usde.balanceOf(treasury);
        return Math.eq(sumUSDeFeesCollected, feeCollectorBalance);
    }

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                         ✦✦✦ LIQUIDITY MANAGEMENT ✦✦✦                         ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    function propertyL() public returns (bool) {
        uint256 liquidityAmountInCooldown;
        uint256 len = unstakers.length;
        for (uint256 i; i < len; i++) {
            UserCooldown memory cooldown = susde.cooldowns(address(unstakers[i]));
            liquidityAmountInCooldown += cooldown.underlyingAmount;
        }
        return Math.eq(liquidityAmountInCooldown, uint256(vm.load(address(arm), bytes32(uint256(100)))));
    }

    function propertyM() public view returns (bool) {
        uint256 nextUnstakerIndex = arm.nextUnstakerIndex();
        return Math.lt(nextUnstakerIndex, arm.MAX_UNSTAKERS());
    }

    function propertyN() public view returns (bool) {
        uint256 len = unstakers.length;
        for (uint256 i; i < len; i++) {
            address unstaker = address(unstakers[i]);
            if (usde.balanceOf(unstaker) != 0 || susde.balanceOf(unstaker) != 0) {
                return false;
            }
        }
        return true;
    }

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                              ✦✦✦ AFTER ALL ✦✦✦                               ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    function propertyAfterAll() public returns (bool) {
        uint256 usdeBalance = usde.balanceOf(address(arm));
        uint256 susdeBalance = susde.balanceOf(address(arm));
        uint256 morphoBalance = morpho.balanceOf(address(arm));
        uint256 armTotalAssets = arm.totalAssets();
        if (this.isConsoleAvailable()) {
            console.log("--- Final Balances ---");
            console.log("ARM USDe balance:\t %18e", usdeBalance);
            console.log("ARM sUSDe balance:\t %18e", susdeBalance);
            console.log("ARM Morpho shares:\t %18e", morphoBalance);
            console.log("ARM total assets:\t %18e", armTotalAssets);
        }
        require(usdeBalance < 1 ether, "USDe balance should be less than 1 ether");
        require(susdeBalance == 0, "sUSDe balance not zero");
        require(morphoBalance == 0, "Morpho shares not zero");
        require(armTotalAssets < 1 ether, "ARM total assets should be less than 1 ether");
        for (uint256 i; i < MAKERS_COUNT; i++) {
            address user = makers[i];
            uint256 totalMinted = mintedUSDe[user];
            uint256 userBalance = usde.balanceOf(user);
            if (!Math.approxGteAbs(userBalance, totalMinted, 1e1)) {
                if (this.isConsoleAvailable()) {
                    console.log(">>> Property After All failed for user %s:", vm.getLabel(user));
                    console.log("    - User USDe balance:   %18e", userBalance);
                    console.log("    - Total minted USDe:   %18e", totalMinted);
                    console.log("    - Difference:          %18e", Math.absDiff(userBalance, totalMinted));
                }
                return false;
            }
        }
        return true;
    }
}
