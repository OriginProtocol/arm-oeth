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
import {IERC20} from "contracts/Interfaces.sol";
import {IERC4626} from "contracts/Interfaces.sol";
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
    // [x] SwapExactTokensForTokens
    // [x] SwapTokensForExactTokens
    // [x] Deposit
    // [x] Allocate
    // [x] CollectFees
    // [x] RequestRedeem
    // [x] ClaimRedeem
    // [ ] RequestBaseWithdrawal
    // [ ] ClaimBaseWithdrawals
    // --- Admin functions
    // [x] SetPrices
    // [x] SetCrossPrice
    // [x] SetFee
    // [x] SetActiveMarket
    // [x] SetARMBuffer
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
    // [x] SetUtilizationRate
    //
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
        uint256 availableLiquidity = usde.balanceOf(address(arm));
        address market = arm.activeMarket();
        if (market != address(0)) {
            availableLiquidity += IERC4626(market).maxWithdraw(address(arm));
        }
        if (assume(claimable != 0)) return;
        // Find a user with a pending request, where the amount is <= claimable
        {
            (user, requestId, claimTimestamp) = Find.getUserRequestWithAmount(
                Find.GetUserRequestWithAmountStruct({
                    arm: address(arm),
                    randomAddressIndex: randomAddressIndex,
                    randomArrayIndex: randomArrayIndex,
                    users: makers,
                    claimable: uint128(claimable),
                    availableLiquidity: uint128(availableLiquidity)
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

    function targetARMSetARMBuffer(uint256 pct) external {
        pct = _bound(pct, 0, 100);

        vm.prank(operator);
        arm.setARMBuffer(pct * 1e16);

        if (this.isConsoleAvailable()) {
            console.log(">>> ARM Buffer:\t Governor set ARM buffer to %s%", pct);
        }
    }

    function targetARMSetActiveMarket(bool isActive) external {
        // If isActive is true it will `setActiveMarket` with MorphoMarket
        // else it will set it to address(0)
        address currentMarket = arm.activeMarket();
        address targetMarket = isActive ? address(market) : address(0);

        // If the current market is the morpho market and we want to deactivate it
        // ensure the is enough liquidity in Morpho to cover the ARM's assets withdrawals
        if (currentMarket == address(market) && !isActive) {
            uint256 shares = market.balanceOf(address(arm));
            uint256 assets = market.convertToAssets(shares);
            uint256 availableLiquidity = morpho.availableLiquidity();
            if (assume(assets < availableLiquidity)) return;
        }

        vm.prank(operator);
        arm.setActiveMarket(targetMarket);

        if (this.isConsoleAvailable()) {
            console.log(
                ">>> ARM SetMarket:\t Governor set active market to %s", isActive ? "Morpho Market" : "No active market"
            );
        }
    }

    function targetARMAllocate() external {
        address currentMarket = arm.activeMarket();
        if (assume(currentMarket != address(0))) return;

        (int256 targetLiquidityDelta, int256 actualLiquidityDelta) = arm.allocate();

        if (this.isConsoleAvailable()) {
            console.log(
                string(
                    abi.encodePacked(
                        ">>> ARM Allocate:\t ARM allocated liquidity to active market. Target delta: ",
                        targetLiquidityDelta < 0 ? "-" : "",
                        "%18e USDe\t Actual delta: ",
                        actualLiquidityDelta < 0 ? "-" : "",
                        "%18e USDe"
                    )
                ),
                abs(targetLiquidityDelta),
                abs(actualLiquidityDelta)
            );
        }
    }

    function targetARMSetPrices(uint256 buyPrice, uint256 sellPrice) external {
        uint256 crossPrice = arm.crossPrice();
        // Bound sellPrice
        sellPrice = uint120(_bound(sellPrice, crossPrice, (1e37 - 1) / 9)); // -> min traderate0 -> 0.9e36
        // Bound buyPrice
        buyPrice = uint120(_bound(buyPrice, 0.9e36, crossPrice - 1)); // -> min traderate1 -> 0.9e36

        vm.prank(operator);
        arm.setPrices(buyPrice, sellPrice);

        if (this.isConsoleAvailable()) {
            console.log(
                ">>> ARM SetPrices:\t Governor set buy price to %36e\t sell price to %36e\t cross price to %36e",
                buyPrice,
                1e72 / sellPrice,
                arm.crossPrice()
            );
        }
    }

    function targetARMSetCrossPrice(uint256 crossPrice) external {
        uint256 maxCrossPrice = 1e36;
        uint256 minCrossPrice = 1e36 - 20e32;
        uint256 sellT1 = 1e72 / (arm.traderate0());
        uint256 buyT1 = arm.traderate1() + 1;
        minCrossPrice = max(minCrossPrice, buyT1);
        maxCrossPrice = min(maxCrossPrice, sellT1);
        if (assume(maxCrossPrice >= minCrossPrice)) return;
        crossPrice = _bound(crossPrice, minCrossPrice, maxCrossPrice);

        if (arm.crossPrice() > crossPrice) {
            if (assume(susde.balanceOf(address(arm)) < 1e12)) return;
        }

        vm.prank(governor);
        arm.setCrossPrice(crossPrice);

        if (this.isConsoleAvailable()) {
            console.log(">>> ARM SetCPrice:\t Governor set cross price to %36e", crossPrice);
        }
    }

    function targetARMSwapExactTokensForTokens(bool token0ForToken1, uint88 amountIn, uint256 randomAddressIndex)
        external
    {
        (IERC20 tokenIn, IERC20 tokenOut) = token0ForToken1
            ? (IERC20(address(usde)), IERC20(address(susde)))
            : (IERC20(address(susde)), IERC20(address(usde)));

        // What's the maximum amountOut we can obtain?
        uint256 maxAmountOut;
        if (address(tokenOut) == address(usde)) {
            uint256 balance = usde.balanceOf(address(arm));
            uint256 outstandingWithdrawals = arm.withdrawsQueued() - arm.withdrawsClaimed();
            maxAmountOut = outstandingWithdrawals >= balance ? 0 : balance - outstandingWithdrawals;
        } else {
            maxAmountOut = susde.balanceOf(address(arm));
        }
        // Ensure there is liquidity available in ARM
        if (assume(maxAmountOut > 1)) return;

        // What's the maximum amountIn we can provide to not exceed maxAmountOut?
        uint256 maxAmountIn = token0ForToken1
            ? (maxAmountOut * 1e36 / arm.traderate0()) * susde.totalAssets() / susde.totalSupply()
            : (maxAmountOut * 1e36 / arm.traderate1()) * susde.totalSupply() / susde.totalAssets();
        if (assume(maxAmountIn > 0)) return;

        // Bound amountIn
        amountIn = uint88(_bound(amountIn, 1, maxAmountIn));
        // Select a random user from makers
        address user = traders[randomAddressIndex % TRADERS_COUNT];

        vm.startPrank(user);
        // Mint amountIn to user
        if (token0ForToken1) {
            MockERC20(address(usde)).mint(user, amountIn);
        } else {
            // Mint too much USDe to user to be able to mint enough sUSDe
            MockERC20(address(usde)).mint(user, uint256(amountIn) * 10);
            // Mint sUSDe to user
            susde.mint(amountIn, user);
            // Burn excess USDe
            MockERC20(address(usde)).burn(user, usde.balanceOf(user));
        }
        // Perform swap
        uint256[] memory obtained = arm.swapExactTokensForTokens(tokenIn, tokenOut, amountIn, 0, user);
        vm.stopPrank();

        if (this.isConsoleAvailable()) {
            console.log(
                string(
                    abi.encodePacked(
                        ">>> ARM SwapEF:\t ",
                        vm.getLabel(user),
                        " swapped %18e ",
                        token0ForToken1 ? "USDe" : "sUSDe",
                        "\t for %18e ",
                        token0ForToken1 ? "sUSDe" : "USDe"
                    )
                ),
                amountIn,
                obtained[1]
            );
        }
    }

    function targetARMSwapTokensForExactTokens(bool token0ForToken1, uint88 amountOut, uint256 randomAddressIndex)
        external
    {
        (IERC20 tokenIn, IERC20 tokenOut) = token0ForToken1
            ? (IERC20(address(usde)), IERC20(address(susde)))
            : (IERC20(address(susde)), IERC20(address(usde)));

        // What's the maximum amountOut we can obtain?
        uint256 maxAmountOut;
        if (address(tokenOut) == address(usde)) {
            uint256 balance = usde.balanceOf(address(arm));
            uint256 outstandingWithdrawals = arm.withdrawsQueued() - arm.withdrawsClaimed();
            maxAmountOut = outstandingWithdrawals >= balance ? 0 : balance - outstandingWithdrawals;
        } else {
            maxAmountOut = susde.balanceOf(address(arm));
        }
        // Ensure there is liquidity available in ARM
        if (assume(maxAmountOut > 1)) return;

        amountOut = uint88(_bound(amountOut, 1, maxAmountOut));

        // What's the maximum amountIn we can provide to not exceed maxAmountOut?
        uint256 convertedAmountOut;
        if (token0ForToken1) {
            convertedAmountOut = (amountOut * susde.totalAssets()) / susde.totalSupply();
        } else {
            convertedAmountOut = (amountOut * susde.totalSupply()) / susde.totalAssets();
        }
        uint256 price = token0ForToken1 ? arm.traderate0() : arm.traderate1();
        uint256 amountIn = ((uint256(convertedAmountOut) * 1e36) / price) + 3 + 10; // slippage + rounding buffer

        // Select a random user from makers
        address user = traders[randomAddressIndex % TRADERS_COUNT];
        vm.startPrank(user);
        // Mint amountIn to user
        if (token0ForToken1) {
            MockERC20(address(usde)).mint(user, amountIn);
        } else {
            // Mint too much USDe to user to be able to mint enough sUSDe
            MockERC20(address(usde)).mint(user, amountIn * 2);
            // Mint sUSDe to user
            susde.mint(amountIn, user);
            // Burn excess USDe
            MockERC20(address(usde)).burn(user, usde.balanceOf(user));
        }
        // Perform swap
        uint256[] memory spent = arm.swapTokensForExactTokens(tokenIn, tokenOut, amountOut, type(uint256).max, user);
        vm.stopPrank();

        if (this.isConsoleAvailable()) {
            console.log(
                string(
                    abi.encodePacked(
                        ">>> ARM SwapFT:\t ",
                        vm.getLabel(user),
                        " swapped %18e ",
                        token0ForToken1 ? "USDe" : "sUSDe",
                        "\t for %18e ",
                        token0ForToken1 ? "sUSDe" : "USDe"
                    )
                ),
                spent[0],
                amountOut
            );
        }
    }

    function targetARMCollectFees() external {
        uint256 fees = arm.feesAccrued();
        uint256 balance = usde.balanceOf(address(arm));
        uint256 outstandingWithdrawals = arm.withdrawsQueued() - arm.withdrawsClaimed();
        if (assume(balance >= fees + outstandingWithdrawals)) return;

        uint256 feesCollected = arm.collectFees();

        if (this.isConsoleAvailable()) {
            console.log(">>> ARM Collect:\t Governor collected %18e USDe in fees", feesCollected);
        }
        require(feesCollected == fees, "Fees collected mismatch");
    }

    function targetARMSetFees(uint256 fee) external {
        // Ensure current fee can be collected
        uint256 fees = arm.feesAccrued();
        if (fees != 0) {
            uint256 balance = usde.balanceOf(address(arm));
            uint256 outstandingWithdrawals = arm.withdrawsQueued() - arm.withdrawsClaimed();
            if (assume(balance >= fees + outstandingWithdrawals)) return;
        }

        uint256 oldFee = arm.fee();
        // Bound fee to [0, 50%]
        fee = _bound(fee, 0, 50);
        vm.prank(governor);
        arm.setFee(fee * 100);

        if (this.isConsoleAvailable()) {
            console.log(">>> ARM SetFees:\t Governor set ARM fee from %s% to %s%", oldFee / 100, fee);
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

        // Ensure there is enough liquidity to withdraw the amount
        uint256 maxWithdrawable = morpho.maxWithdraw(harry);
        if (assume(amount <= maxWithdrawable)) return;

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

    function targetMorphoSetUtilizationRate(uint256 pct) external {
        pct = _bound(pct, 0, 100);

        morpho.setUtilizationRate(pct * 1e16);

        if (this.isConsoleAvailable()) {
            console.log(">>> Morpho UseRate:\t Governor set utilization rate to %s%", pct);
        }
    }
}
