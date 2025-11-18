// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Setup} from "./Setup.sol";
import {console} from "forge-std/console.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {StdStyle} from "forge-std/StdStyle.sol";

// Solmate
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

// Contracts
import {UserCooldown} from "contracts/Interfaces.sol";

/// @title TargetFunctions
/// @notice TargetFunctions contract for tests, containing the target functions that should be tested.
///         This is the entry point with the contract we are testing. Ideally, it should never revert.
abstract contract TargetFunctions is Setup, StdUtils {
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                              ✦✦✦ ETHENA ARM ✦✦✦                              ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [ ] SwapExactTokensForTokens
    // [ ] SwapTokensForExactTokens
    // [ ] Deposit
    // [ ] Allocate
    // [ ] CollectFees
    // [ ] RequestRedeem
    // [ ] ClaimRedeem
    // [ ] RequestBaseWithdrawal
    // [ ] ClaimBaseWithdrawals
    // --- Admin functions
    // [ ] SetPrices
    // [ ] SetCrossPrice
    // [ ] SetFee
    // [ ] SetActiveMarket
    // [ ] SetARMBuffer
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                                ✦✦✦ SUSDE ✦✦✦                                 ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] Deposit
    // [x] CoolDownShares
    // [x] Unstake
    // --- Admin functions
    // [x] TransferInRewards
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                                ✦✦✦ MORPHO ✦✦✦                                ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [x] Deposit
    // [x] Withdraw
    // [x] TransferInRewards
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                                   ✦✦✦  ✦✦✦                                   ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                                ✦✦✦ SUSDE ✦✦✦                                 ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    function targetSUSDeDeposit(uint88 amount) external {
        // Ensure we don't mint 0 shares.
        uint256 totalAssets = susde.totalAssets();
        uint256 totalSupply = susde.totalSupply();
        uint256 minAmount = totalAssets / totalSupply + 1;
        // Prevent zero deposits
        amount = uint88(_bound(amount, minAmount, type(uint88).max));

        // Mint amount to grace
        MockERC20(address(usde)).mint(grace, amount);

        // Deposit as grace
        vm.prank(grace);
        uint256 shares = susde.deposit(amount, grace);

        if (this.isConsoleAvailable()) {
            console.log(
                ">>> sUSDe Deposit:\t Grace deposited %18e USDe\t and received %18e sUSDe shares", amount, shares
            );
        }
    }

    function targetSUSDeCooldownShares(uint88 shareAmount) external {
        // Cache balance
        uint256 balance = susde.balanceOf(grace);

        // Assume balance not zero
        if (assume(balance > 1)) return;

        // Bound shareAmount to [1, balance]
        shareAmount = uint88(_bound(shareAmount, 1, balance));

        // Cooldown shares as grace
        vm.prank(grace);
        uint256 amount = susde.cooldownShares(shareAmount);
        if (this.isConsoleAvailable()) {
            console.log(
                ">>> sUSDe Cooldown:\t Grace cooled down %18e sUSDe shares\t for %18e USDe underlying",
                shareAmount,
                amount
            );
        }
    }

    function targetSUSDeUnstake() external {
        // Check grace's cooldown
        UserCooldown memory cooldown = susde.cooldowns(grace);

        // Ensure grace has a valid cooldown
        if (assume(cooldown.cooldownEnd != 0)) return;

        // Fast forward to after cooldown end
        if (this.isConsoleAvailable()) {
            console.log(
                StdStyle.yellow(
                    string(
                        abi.encodePacked(
                            ">>> Time jump:\t Fast forwarded to: ",
                            vm.toString(cooldown.cooldownEnd),
                            "  (+ ",
                            vm.toString(cooldown.cooldownEnd - block.timestamp),
                            "s)"
                        )
                    )
                )
            );
        }
        vm.warp(cooldown.cooldownEnd);

        // Unstake as grace
        vm.prank(grace);
        susde.unstake(grace);

        if (this.isConsoleAvailable()) {
            console.log(
                ">>> sUSDe Unstake:\t Grace unstaked %18e USDe underlying after cooldown", cooldown.underlyingAmount
            );
        }
        MockERC20(address(usde)).burn(grace, cooldown.underlyingAmount);
    }

    function targetSUSDeTransferInRewards(uint8 bps) external {
        // Ensure enough time has passed since last distribution
        uint256 lastDistribution = susde.lastDistributionTimestamp();
        if (block.timestamp - lastDistribution < 8 hours) {
            // Fast forward time to allow rewards distribution
            if (this.isConsoleAvailable()) {
                console.log(
                    StdStyle.yellow(
                        string(
                            abi.encodePacked(
                                ">>> Time jump:\t Fast forwarded to: ",
                                vm.toString(lastDistribution + 8 hours),
                                "  (+ ",
                                vm.toString((lastDistribution + 8 hours) - block.timestamp),
                                "s)"
                            )
                        )
                    )
                );
                vm.warp(lastDistribution + 8 hours);
            }
        }

        uint256 balance = usde.balanceOf(address(susde));
        // Rewards can be distributed 3/days max. 1bps at every distribution -> 10 APR.
        bps = uint8(_bound(bps, 1, 10));
        uint256 rewards = (balance * bps) / 10_000;
        MockERC20(address(usde)).mint(governor, rewards);
        vm.prank(governor);
        susde.transferInRewards(rewards);

        if (this.isConsoleAvailable()) {
            console.log(">>> sUSDe Rewards:\t Governor transferred in %18e USDe as rewards, bps: %d", rewards, bps);
        }
    }

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                                ✦✦✦ MORPHO ✦✦✦                                ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    function targetMorphoDeposit(uint88 amount) external {
        // Ensure we don't mint 0 shares.
        uint256 totalAssets = morpho.totalAssets();
        uint256 totalSupply = morpho.totalSupply();
        uint256 minAmount = totalAssets / totalSupply + 1;
        // Prevent zero deposits
        amount = uint88(_bound(amount, minAmount, type(uint88).max));

        // Mint amount to harry
        MockERC20(address(usde)).mint(harry, amount);

        // Deposit as harry
        vm.prank(harry);
        uint256 shares = morpho.deposit(amount, harry);

        if (this.isConsoleAvailable()) {
            console.log(
                ">>> Morpho Deposit:\t Harry deposited %18e USDe\t and received %18e Morpho shares", amount, shares
            );
        }
    }

    function targetMorphoWithdraw(uint88 amount) external {
        // Check harry's balance
        uint256 balance = morpho.balanceOf(harry);

        // Assume balance not zero
        if (assume(balance > 1)) return;

        // Bound shareAmount to [1, balance]
        amount = uint88(_bound(amount, 1, balance));

        // Withdraw as harry
        vm.prank(harry);
        uint256 shares = morpho.withdraw(amount, harry, harry);
        if (this.isConsoleAvailable()) {
            console.log(
                ">>> Morpho Withdraw:\t Harry withdrew %18e Morpho shares\t for %18e USDe underlying", shares, amount
            );
        }

        MockERC20(address(usde)).burn(harry, amount);
    }

    function targetMorphoTransferInRewards(uint8 bps) external {
        uint256 balance = usde.balanceOf(address(morpho));
        bps = uint8(_bound(bps, 1, 10));
        uint256 rewards = (balance * bps) / 10_000;
        MockERC20(address(usde)).mint(address(morpho), rewards);

        if (this.isConsoleAvailable()) {
            console.log(">>> Morpho Rewards:\t Transferred in %18e USDe as rewards, bps: %d", rewards, bps);
        }
    }
}
