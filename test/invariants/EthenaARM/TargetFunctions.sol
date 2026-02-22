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
import {Math} from "./helpers/Math.sol";

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
    // [x] RequestBaseWithdrawal
    // [x] ClaimBaseWithdrawals
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
    function targetARMDeposit(uint88 amount, uint256 randomAddressIndex) external ensureExchangeRateIncrease {
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

        if (isConsoleAvailable) {
            console.log(
                ">>> ARM Deposit:\t %s deposited %18e USDe\t and received %18e ARM shares",
                vm.getLabel(user),
                amount,
                shares
            );
        }

        sumUSDeUserDeposit += amount;
        mintedUSDe[user] += amount;
    }

    function targetARMRequestRedeem(uint88 shareAmount, uint248 randomAddressIndex)
        external
        ensureExchangeRateIncrease
    {
        address user;
        uint256 balance;
        (user, balance) = Find.getUserWithARMShares(makers, address(arm));
        if (assume(user != address(0))) return;
        // Bound shareAmount to [1, balance]
        shareAmount = uint88(_bound(shareAmount, 1, balance));

        // Request redeem as user
        vm.prank(user);
        (uint256 requestId, uint256 amount) = arm.requestRedeem(shareAmount);
        pendingRequests[user].push(requestId);

        if (isConsoleAvailable) {
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

        sumUSDeUserRequest += amount;
    }

    function targetARMClaimRedeem(uint248 randomAddressIndex, uint248 randomArrayIndex)
        external
        ensureExchangeRateIncrease
        ensureTimeIncrease
    {
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
            if (isConsoleAvailable) {
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
        uint256 balanceBefore = usde.balanceOf(address(arm));
        vm.prank(user);
        uint256 amount = arm.claimRedeem(requestId);

        if (isConsoleAvailable) {
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

        sumUSDeUserRedeem += amount;
        if (balanceBefore < amount) {
            // This means we had to withdraw from market
            sumUSDeMarketWithdraw += amount - balanceBefore;
        }
    }

    function targetARMSetARMBuffer(uint256 pct) external ensureExchangeRateIncrease {
        pct = _bound(pct, 0, 100);

        vm.prank(operator);
        arm.setARMBuffer(pct * 1e16);

        if (isConsoleAvailable) {
            console.log(">>> ARM Buffer:\t Governor set ARM buffer to %s%", pct);
        }
    }

    function targetARMSetActiveMarket(bool isActive) external ensureExchangeRateIncrease {
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

        uint256 balanceBefore = usde.balanceOf(address(arm));
        vm.prank(operator);
        arm.setActiveMarket(targetMarket);
        uint256 balanceAfter = usde.balanceOf(address(arm));

        if (isConsoleAvailable) {
            console.log(
                ">>> ARM SetMarket:\t Governor set active market to %s", isActive ? "Morpho Market" : "No active market"
            );
        }

        int256 diff = int256(balanceAfter) - int256(balanceBefore);
        if (diff > 0) {
            sumUSDeMarketWithdraw += uint256(diff);
        } else {
            sumUSDeMarketDeposit += uint256(-diff);
        }
    }

    function targetARMAllocate() external ensureExchangeRateIncrease {
        address currentMarket = arm.activeMarket();
        if (assume(currentMarket != address(0))) return;

        (int256 targetLiquidityDelta, int256 actualLiquidityDelta) = arm.allocate();

        if (isConsoleAvailable) {
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
                Math.abs(targetLiquidityDelta),
                Math.abs(actualLiquidityDelta)
            );
        }

        if (actualLiquidityDelta > 0) {
            sumUSDeMarketDeposit += uint256(actualLiquidityDelta);
        } else {
            sumUSDeMarketWithdraw += uint256(-actualLiquidityDelta);
        }
    }

    function targetARMSetPrices(uint256 buyPrice, uint256 sellPrice) external ensureExchangeRateIncrease {
        uint256 crossPrice = arm.crossPrice();
        // Bound sellPrice
        sellPrice = uint120(_bound(sellPrice, crossPrice, (1e37 - 1) / 9)); // -> min traderate0 -> 0.9e36
        // Bound buyPrice
        buyPrice = uint120(_bound(buyPrice, 0.9e36, crossPrice - 1)); // -> min traderate1 -> 0.9e36

        vm.prank(operator);
        arm.setPrices(buyPrice, sellPrice);

        if (isConsoleAvailable) {
            console.log(
                ">>> ARM SetPrices:\t Governor set buy price to %36e\t sell price to %36e\t cross price to %36e",
                buyPrice,
                1e72 / sellPrice,
                arm.crossPrice()
            );
        }
    }

    function targetARMSetCrossPrice(uint256 crossPrice) external ensureExchangeRateIncrease {
        uint256 maxCrossPrice = 1e36;
        uint256 minCrossPrice = 1e36 - 20e32;
        uint256 sellT1 = 1e72 / (arm.traderate0());
        uint256 buyT1 = arm.traderate1() + 1;
        minCrossPrice = Math.max(minCrossPrice, buyT1);
        maxCrossPrice = Math.min(maxCrossPrice, sellT1);
        if (assume(maxCrossPrice >= minCrossPrice)) return;
        crossPrice = _bound(crossPrice, minCrossPrice, maxCrossPrice);

        if (arm.crossPrice() > crossPrice) {
            if (assume(susde.balanceOf(address(arm)) < 1e12)) return;
        }

        vm.prank(governor);
        arm.setCrossPrice(crossPrice);

        if (isConsoleAvailable) {
            console.log(">>> ARM SetCPrice:\t Governor set cross price to %36e", crossPrice);
        }
    }

    function targetARMSwapExactTokensForTokens(bool token0ForToken1, uint88 amountIn, uint256 randomAddressIndex)
        external
        ensureExchangeRateIncrease
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

        if (isConsoleAvailable) {
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

        require(obtained[0] == amountIn, "Amount in mismatch");
        if (token0ForToken1) {
            sumUSDeSwapIn += obtained[0];
            sumSUSDeSwapOut += obtained[1];
        } else {
            sumSUSDeSwapIn += obtained[0];
            sumUSDeSwapOut += obtained[1];
        }
    }

    function targetARMSwapTokensForExactTokens(bool token0ForToken1, uint88 amountOut, uint256 randomAddressIndex)
        external
        ensureExchangeRateIncrease
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
        uint256[] memory obtained = arm.swapTokensForExactTokens(tokenIn, tokenOut, amountOut, type(uint256).max, user);
        vm.stopPrank();

        if (isConsoleAvailable) {
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
                obtained[0],
                amountOut
            );
        }

        require(obtained[1] == amountOut, "Amount out mismatch");
        if (token0ForToken1) {
            sumUSDeSwapIn += obtained[0];
            sumSUSDeSwapOut += obtained[1];
        } else {
            sumSUSDeSwapIn += obtained[0];
            sumUSDeSwapOut += obtained[1];
        }
    }

    function targetARMCollectFees() external ensureExchangeRateIncrease {
        uint256 feesAccrued = arm.feesAccrued();
        uint256 balance = usde.balanceOf(address(arm));
        uint256 outstandingWithdrawals = arm.withdrawsQueued() - arm.withdrawsClaimed();
        if (assume(balance >= feesAccrued + outstandingWithdrawals)) return;

        uint256 feesCollected = arm.collectFees();

        if (isConsoleAvailable) {
            console.log(">>> ARM Collect:\t Governor collected %18e USDe in fees", feesCollected);
        }
        require(feesCollected == feesAccrued, "Fees collected mismatch");

        sumUSDeFeesCollected += feesCollected;
    }

    function targetARMSetFees(uint256 fee) external ensureExchangeRateIncrease {
        // Ensure current fee can be collected
        uint256 feesAccrued = arm.feesAccrued();
        if (feesAccrued != 0) {
            uint256 balance = usde.balanceOf(address(arm));
            uint256 outstandingWithdrawals = arm.withdrawsQueued() - arm.withdrawsClaimed();
            if (assume(balance >= feesAccrued + outstandingWithdrawals)) return;
        }

        uint256 oldFee = arm.fee();
        // Bound fee to [0, 50%]
        fee = _bound(fee, 0, 50);
        vm.prank(governor);
        arm.setFee(fee * 100);

        if (isConsoleAvailable) {
            console.log(">>> ARM SetFees:\t Governor set ARM fee from %s% to %s%", oldFee / 100, fee);
        }

        sumUSDeFeesCollected += feesAccrued;
    }

    function targetARMRequestBaseWithdrawal(uint88 amount) external ensureExchangeRateIncrease {
        uint256 balance = susde.balanceOf(address(arm));
        if (assume(balance > 1)) return;
        amount = uint88(_bound(amount, 1, balance));

        // Ensure there is an unstaker available
        uint256 nextIndex = arm.nextUnstakerIndex();
        address unstaker = arm.unstakers(nextIndex);
        UserCooldown memory cooldown = susde.cooldowns(unstaker);
        // If next unstaker has an active cooldown, this means all unstakers are in cooldown
        // -> no unstaker available
        if (assume(cooldown.underlyingAmount == 0)) return;

        // Ensure time delay has passed
        uint32 lastRequestTimestamp = arm.lastRequestTimestamp();
        if (block.timestamp < lastRequestTimestamp + 3 hours) {
            if (isConsoleAvailable) {
                console.log(
                    StdStyle.yellow(
                        string(
                            abi.encodePacked(
                                ">>> Time jump:\t Fast forwarded to: ",
                                vm.toString(lastRequestTimestamp + 3 hours),
                                "  (+ ",
                                vm.toString((lastRequestTimestamp + 3 hours) - block.timestamp),
                                "s)"
                            )
                        )
                    )
                );
            }
            vm.warp(lastRequestTimestamp + 3 hours);
        }

        vm.prank(operator);
        arm.requestBaseWithdrawal(amount);

        unstakerIndices.push(nextIndex);

        if (isConsoleAvailable) {
            console.log(
                ">>> ARM ReqBaseW:\t Operator requested base withdrawal of %18e sUSDe underlying, using unstakers #%s",
                amount,
                nextIndex
            );
        }

        sumSUSDeBaseRedeem += amount;
    }

    function targetARMClaimBaseWithdrawals(uint256 randomAddressIndex)
        external
        ensureExchangeRateIncrease
        ensureTimeIncrease
    {
        if (assume(unstakerIndices.length != 0)) return;
        // Select a random unstaker index from used unstakers
        uint256 selectedIndex = unstakerIndices[randomAddressIndex % unstakerIndices.length];
        address unstaker = arm.unstakers(uint8(selectedIndex));
        UserCooldown memory cooldown = susde.cooldowns(address(unstaker));
        uint256 endTimestamp = cooldown.cooldownEnd;

        // Fast forward time if needed
        if (block.timestamp < endTimestamp) {
            if (isConsoleAvailable) {
                console.log(
                    StdStyle.yellow(
                        string(
                            abi.encodePacked(
                                ">>> Time jump:\t Fast forwarded to: ",
                                vm.toString(endTimestamp),
                                "  (+ ",
                                vm.toString(endTimestamp - block.timestamp),
                                "s)"
                            )
                        )
                    )
                );
            }
            vm.warp(endTimestamp);
        }

        vm.prank(operator);
        arm.claimBaseWithdrawals(uint8(selectedIndex));

        // Remove selectedIndex from unstakerIndices, without preserving order
        unstakerIndices[randomAddressIndex % unstakerIndices.length] = unstakerIndices[unstakerIndices.length - 1];
        unstakerIndices.pop();

        if (isConsoleAvailable) {
            console.log(
                string(
                    abi.encodePacked(
                        ">>> ARM ClaimBaseW:\t Operator claimed base withdrawals using %s\t ", "who unstaked %18e USDe"
                    )
                ),
                vm.getLabel(unstaker),
                cooldown.underlyingAmount
            );
        }

        sumUSDeBaseRedeem += cooldown.underlyingAmount;
    }

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                                ✦✦✦ SUSDE ✦✦✦                                 ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    function targetSUSDeDeposit(uint88 amount) external ensureExchangeRateIncrease {
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

        if (isConsoleAvailable) {
            console.log(
                ">>> sUSDe Deposit:\t Grace deposited %18e USDe\t and received %18e sUSDe shares", amount, shares
            );
        }
    }

    function targetSUSDeCooldownShares(uint88 shareAmount) external ensureExchangeRateIncrease {
        // Cache balance
        uint256 balance = susde.balanceOf(grace);

        // Assume balance not zero
        if (assume(balance > 1)) return;

        // Bound shareAmount to [1, balance]
        shareAmount = uint88(_bound(shareAmount, 1, balance));

        // Cooldown shares as grace
        vm.prank(grace);
        uint256 amount = susde.cooldownShares(shareAmount);
        if (isConsoleAvailable) {
            console.log(
                ">>> sUSDe Cooldown:\t Grace cooled down %18e sUSDe shares\t for %18e USDe underlying",
                shareAmount,
                amount
            );
        }
    }

    function targetSUSDeUnstake() external ensureExchangeRateIncrease ensureTimeIncrease {
        // Check grace's cooldown
        UserCooldown memory cooldown = susde.cooldowns(grace);

        // Ensure grace has a valid cooldown
        if (assume(cooldown.cooldownEnd != 0)) return;

        // Fast forward to after cooldown end if needed
        if (block.timestamp < cooldown.cooldownEnd) {
            if (isConsoleAvailable) {
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

        if (isConsoleAvailable) {
            console.log(
                ">>> sUSDe Unstake:\t Grace unstaked %18e USDe underlying after cooldown", cooldown.underlyingAmount
            );
        }
        MockERC20(address(usde)).burn(grace, cooldown.underlyingAmount);
    }

    function targetSUSDeTransferInRewards(uint8 bps) external ensureExchangeRateIncrease ensureTimeIncrease {
        // Ensure enough time has passed since last distribution
        uint256 lastDistribution = susde.lastDistributionTimestamp();
        if (block.timestamp < 8 hours + lastDistribution) {
            // Fast forward time to allow rewards distribution
            if (isConsoleAvailable) {
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

        if (isConsoleAvailable) {
            console.log(">>> sUSDe Rewards:\t Governor transferred in %18e USDe as rewards, bps: %d", rewards, bps);
        }
    }

    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                                ✦✦✦ MORPHO ✦✦✦                                ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    function targetMorphoDeposit(uint88 amount) external ensureExchangeRateIncrease {
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

        if (isConsoleAvailable) {
            console.log(
                ">>> Morpho Deposit:\t Harry deposited %18e USDe\t and received %18e Morpho shares", amount, shares
            );
        }
    }

    function targetMorphoWithdraw(uint88 amount) external ensureExchangeRateIncrease {
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
        if (isConsoleAvailable) {
            console.log(
                ">>> Morpho Withdraw:\t Harry withdrew %18e Morpho shares\t for %18e USDe underlying", shares, amount
            );
        }

        MockERC20(address(usde)).burn(harry, amount);
    }

    function targetMorphoTransferInRewards(uint8 bps) external ensureExchangeRateIncrease {
        uint256 balance = usde.balanceOf(address(morpho));
        bps = uint8(_bound(bps, 1, 10));
        uint256 rewards = (balance * bps) / 10_000;
        MockERC20(address(usde)).mint(address(morpho), rewards);

        if (isConsoleAvailable) {
            console.log(">>> Morpho Rewards:\t Transferred in %18e USDe as rewards, bps: %d", rewards, bps);
        }
    }

    function targetMorphoSetUtilizationRate(uint256 pct) external ensureExchangeRateIncrease {
        pct = _bound(pct, 0, 100);

        morpho.setUtilizationRate(pct * 1e16);

        if (isConsoleAvailable) {
            console.log(">>> Morpho UseRate:\t Governor set utilization rate to %s%", pct);
        }
    }

    function _targetAfterAll() internal {
        // In this function, we will simulate shutting down the ARM. This involves letting all users redeem their funds.
        // This is important to ensure that the ARM can handle a complete withdrawal scenario without issues.
        // This involves:
        // 1. Claim all sUSDe base withdrawals
        // 2. Request base withdrawal of the remaining sUSDe
        // 3. Claim previous base withdrawals. At this point we shouldn't have any sUSDe left in the ARM.
        // 4. Remove position from Morpho if any.
        // 5. Let all ARM users (including dead address) redeem their shares.
        // 6. Claim fees accrued.

        // 1. Claim all sUSDe base withdrawals
        // Fast forward time to allow claiming all previous base withdrawals
        vm.warp(block.timestamp + 7 days);
        for (uint256 i; i < unstakerIndices.length; i++) {
            arm.claimBaseWithdrawals(uint8(unstakerIndices[i]));
        }

        // 2. Request base withdrawal of the remaining sUSDe
        uint256 susdeBalance = susde.balanceOf(address(arm));
        uint256 nextIndex = arm.nextUnstakerIndex();
        if (susdeBalance > 0) {
            vm.prank(operator);
            arm.requestBaseWithdrawal(susdeBalance);
        }

        // 3. Claim previous base withdrawals. At this point we shouldn't have any sUSDe left in the ARM.
        if (susdeBalance > 0) {
            // Fast forward time to allow claiming the last base withdrawal
            vm.warp(block.timestamp + 7 days);
            arm.claimBaseWithdrawals(uint8(nextIndex));
        }
        require(susde.balanceOf(address(arm)) == 0, "ARM still has sUSDe balance");

        // 4. Remove position from Morpho if any.
        address activeMarket = arm.activeMarket();
        if (activeMarket != address(0)) {
            morpho.setUtilizationRate(0);
            vm.prank(operator);
            arm.setActiveMarket(address(0));
        }

        // 5. Let all ARM users redeem their shares.
        for (uint256 i; i < MAKERS_COUNT; i++) {
            address user = makers[i];
            uint256 balance = arm.balanceOf(user);
            if (balance > 0) {
                vm.prank(user);
                arm.requestRedeem(balance);
            }
        }

        // Fast forward time to allow claiming all redemptions
        vm.warp(block.timestamp + DEFAULT_CLAIM_DELAY);
        uint256 nextWithdrawalIndex = arm.nextWithdrawalIndex();
        for (uint256 i; i < nextWithdrawalIndex; i++) {
            (address user, bool claimed,,,,) = arm.withdrawalRequests(i);
            if (claimed) continue;
            vm.prank(user);
            arm.claimRedeem(i);
        }

        // 6. Claim fees accrued.
        arm.collectFees();
    }
}
