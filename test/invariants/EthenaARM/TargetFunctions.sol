// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Setup} from "./Setup.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

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
    // [ ] Deposit
    // [ ] CoolDownShares
    // [ ] Unstake
    // --- Admin functions
    // [ ] TransferInRewards
    //
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                                ✦✦✦ MORPHO ✦✦✦                                ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [ ] Deposit
    // [ ] Withdraw
    // [ ] TransferInRewards
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
        susde.deposit(amount, grace);
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
        susde.cooldownShares(shareAmount);
    }

    function targetSUSDeUnstake() external {
        // Check grace's cooldown
        UserCooldown memory cooldown = susde.cooldowns(grace);

        // Ensure grace has a valid cooldown
        if (assume(cooldown.cooldownEnd != 0)) return;

        // Fast forward to after cooldown end
        vm.warp(cooldown.cooldownEnd + 1);

        // Unstake as grace
        vm.prank(grace);
        susde.unstake(grace);

        MockERC20(address(usde)).burn(grace, cooldown.underlyingAmount);
    }

    function targetSUSDeTransferInRewards(uint8 bps) external {
        // Ensure enough time has passed since last distribution
        uint256 lastDistribution = susde.lastDistributionTimestamp();
        if (block.timestamp - lastDistribution < 8 hours) {
            // Fast forward time to allow rewards distribution
            vm.warp(lastDistribution + 8 hours + 1);
        }

        uint256 balance = usde.balanceOf(address(susde));
        // Rewards can be distributed 3/days max. 1bps at every distribution -> 10 APR.
        bps = uint8(_bound(bps, 1, 10));
        uint256 rewards = (balance * bps) / 10_000;
        MockERC20(address(usde)).mint(governor, rewards);
        vm.prank(governor);
        susde.transferInRewards(rewards);
    }
}
