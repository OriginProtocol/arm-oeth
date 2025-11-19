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

// Helpers
import {Find} from "./helpers/Find.sol";

/// @title TargetFunctions
/// @notice TargetFunctions contract for tests, containing the target functions that should be tested.
///         This is the entry point with the contract we are testing. Ideally, it should never revert.
abstract contract TargetFunctions is Setup, StdUtils {
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                              ✦✦✦ ETHENA ARM ✦✦✦                              ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // [ ] SwapExactTokensForTokens
    // [ ] SwapTokensForExactTokens
    // [x] Deposit
    // [ ] Allocate
    // [ ] CollectFees
    // [x] RequestRedeem
    // [x] ClaimRedeem
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
    // ║                              ✦✦✦ ETHENA ARM ✦✦✦                              ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    function targetARMDeposit(uint88 amount, uint256 randomAddressIndex) external {
        // Select a random user from makers
        address user = makers[randomAddressIndex % MAKERS_COUNT];

        uint256 totalSupply = arm.totalSupply();
        uint256 totalAssets = arm.totalAssets();
        // Min amount to avoid 0 shares minting
        uint256 minAmount = totalAssets / totalSupply + 1;
        amount = uint88(_bound(amount, minAmount, type(uint88).max));

        // Mint amount to user
        MockERC20(address(usde)).mint(user, amount);
        // Deposit as user
        vm.prank(user);
        uint256 shares = arm.deposit(amount, user);

        if (this.isConsoleAvailable()) {
            console.log(
                ">>> ARM Deposit:\t %s deposited %18e USDe\t and received %18e ARM shares",
                vm.getLabel(user),
                amount,
                shares
            );
        }
    }

    function targetARMRequestRedeem(uint88 shareAmount, uint248 randomAddressIndex) external {
        address user;
        uint256 balance;
        // Todo: mirgate it to Find library
        for (uint256 i; i < MAKERS_COUNT; i++) {
            address _user = makers[(randomAddressIndex + i) % MAKERS_COUNT];
            uint256 _balance = arm.balanceOf(_user);
            // Found a user with non-zero balance
            if (_balance > 1) {
                (user, balance) = (_user, _balance);
                break;
            }
        }
        if (assume(user != address(0))) return;
        // Bound shareAmount to [1, balance]
        shareAmount = uint88(_bound(shareAmount, 1, balance));

        // Request redeem as user
        vm.prank(user);
        (uint256 requestId, uint256 amount) = arm.requestRedeem(shareAmount);
        pendingRequests[user].push(requestId);

        if (this.isConsoleAvailable()) {
            console.log(
                string(
                    abi.encodePacked(
                        ">>> ARM Request:\t ",
                        vm.getLabel(user),
                        " requested redeem of %18e ARM shares\t for %18e USDe underlying\t Request ID: %d"
                    )
                ),
                shareAmount,
                amount,
                requestId
            );
        }
    }

    function targetARMClaimRedeem(uint248 randomAddressIndex, uint248 randomArrayIndex) external ensureTimeIncrease {
        address user;
        uint256 requestId;
        uint256 claimTimestamp;
        uint256 claimable = arm.claimable();
        if (assume(claimable != 0)) return;
        // Find a user with a pending request, where the amount is <= claimable
        {
            (user, requestId, claimTimestamp) = Find.getUserRequestWithAmount(
                Find.GetUserRequestWithAmountStruct({
                    arm: address(arm),
                    randomAddressIndex: randomAddressIndex,
                    randomArrayIndex: randomArrayIndex,
                    users: makers,
                    targetAmount: claimable
                }),
                pendingRequests
            );
            if (assume(user != address(0))) return;
        }

        // Fast forward time if needed
        if (block.timestamp < claimTimestamp) {
            if (this.isConsoleAvailable()) {
                console.log(
                    StdStyle.yellow(
                        string(
                            abi.encodePacked(
                                ">>> Time jump:\t Fast forwarded to: ",
                                vm.toString(claimTimestamp),
                                "  (+ ",
                                vm.toString(claimTimestamp - block.timestamp),
                                "s)"
                            )
                        )
                    )
                );
            }
            vm.warp(claimTimestamp);
        }

        // Claim redeem as user
        vm.prank(user);
        uint256 amount = arm.claimRedeem(requestId);

        if (this.isConsoleAvailable()) {
            console.log(
                string(
                    abi.encodePacked(
                        ">>> ARM Claim:\t ",
                        vm.getLabel(user),
                        " claimed redeem request ID %d\t and received %18e USDe underlying"
                    )
                ),
                requestId,
                amount
            );
        }
    }

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

    function targetSUSDeUnstake() external ensureTimeIncrease {
        // Check grace's cooldown
        UserCooldown memory cooldown = susde.cooldowns(grace);

        // Ensure grace has a valid cooldown
        if (assume(cooldown.cooldownEnd != 0)) return;

        // Fast forward to after cooldown end if needed
        if (block.timestamp < cooldown.cooldownEnd) {
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
        }

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

    function targetSUSDeTransferInRewards(uint8 bps) external ensureTimeIncrease {
        // Ensure enough time has passed since last distribution
        uint256 lastDistribution = susde.lastDistributionTimestamp();
        if (block.timestamp < 8 hours + lastDistribution) {
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
