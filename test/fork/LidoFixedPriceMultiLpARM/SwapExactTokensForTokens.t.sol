// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

import {IERC20} from "contracts/Interfaces.sol";

contract Fork_Concrete_LidoARM_SwapExactTokensForTokens_Test is Fork_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////
    uint256 private constant MIN_PRICE0 = 980e33; // 0.98
    uint256 private constant MAX_PRICE0 = 1_000e33; // 1.00
    uint256 private constant MIN_PRICE1 = 1_000e33; // 1.00
    uint256 private constant MAX_PRICE1 = 1_020e33; // 1.02
    uint256 private constant MAX_WETH_RESERVE = 1_000_000 ether; // 1M WETH, no limit, but need to be consistent.
    uint256 private constant MAX_STETH_RESERVE = 2_000_000 ether; // 2M stETH, limited by wsteth balance of steth.

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        deal(address(weth), address(this), 1_000 ether);
        deal(address(steth), address(this), 1_000 ether);

        deal(address(weth), address(lidoARM), 1_000 ether);
        deal(address(steth), address(lidoARM), 1_000 ether);
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_SwapExactTokensForTokens_Because_InvalidTokenOut1() public {
        lidoARM.token0();
        vm.expectRevert("ARM: Invalid out token");
        lidoARM.swapExactTokensForTokens(
            steth, // inToken
            badToken, // outToken
            1, // amountIn
            1, // amountOutMin
            address(this) // to
        );
    }

    function test_RevertWhen_SwapExactTokensForTokens_Because_InvalidTokenOut0() public {
        vm.expectRevert("ARM: Invalid out token");
        lidoARM.swapExactTokensForTokens(
            weth, // inToken
            badToken, // outToken
            1, // amountIn
            1, // amountOutMin
            address(this) // to
        );
    }

    function test_RevertWhen_SwapExactTokensForTokens_Because_InvalidTokenIn() public {
        vm.expectRevert("ARM: Invalid in token");
        lidoARM.swapExactTokensForTokens(
            badToken, // inToken
            steth, // outToken
            1, // amountIn
            1, // amountOutMin
            address(this) // to
        );
    }

    function test_RevertWhen_SwapExactTokensForTokens_Because_BothInvalidTokens() public {
        vm.expectRevert("ARM: Invalid in token");
        lidoARM.swapExactTokensForTokens(
            badToken, // inToken
            badToken, // outToken
            1, // amountIn
            1, // amountOutMin
            address(this) // to
        );
    }

    function test_RevertWhen_SwapExactTokensForTokens_Because_NotEnoughTokenIn() public {
        uint256 initialBalance = weth.balanceOf(address(this));

        vm.expectRevert();
        lidoARM.swapExactTokensForTokens(
            weth, // inToken
            steth, // outToken
            initialBalance + 1, // amountIn
            0, // amountOutMin
            address(this) // to
        );

        initialBalance = steth.balanceOf(address(this));
        vm.expectRevert("BALANCE_EXCEEDED"); // Lido error
        lidoARM.swapExactTokensForTokens(
            steth, // inToken
            weth, // outToken
            initialBalance + 3, // amountIn
            0, // amountOutMin
            address(this) // to
        );
    }

    function test_RevertWhen_SwapExactTokensForTokens_Because_NotEnoughTokenOut() public {
        uint256 initialBalance = steth.balanceOf(address(lidoARM));
        deal(address(weth), address(this), initialBalance * 2);

        vm.expectRevert("BALANCE_EXCEEDED"); // Lido error
        lidoARM.swapExactTokensForTokens(
            weth, // inToken
            steth, // outToken
            initialBalance * 2, // amountIn
            0, // amountOutMin
            address(this) // to
        );

        initialBalance = weth.balanceOf(address(lidoARM));
        deal(address(steth), address(this), initialBalance * 2);
        vm.expectRevert();
        lidoARM.swapExactTokensForTokens(
            steth, // inToken
            weth, // outToken
            initialBalance * 2, // amountIn
            0, // amountOutMin
            address(this) // to
        );
    }

    function test_RevertWhen_SwapExactTokensForTokens_Because_InsufficientOutputAmount() public {
        deal(address(steth), address(lidoARM), 100 wei);

        // Test for this function signature: swapExactTokensForTokens(IERC20,IERC20,uint56,uint256,address)
        vm.expectRevert("ARM: Insufficient output amount");
        lidoARM.swapExactTokensForTokens(
            weth, // inToken
            steth, // outToken
            1, // amountIn
            1_000 ether, // amountOutMin
            address(this) // to
        );

        // Test for this function signature: swapExactTokensForTokens(uint256,uint256,address[],address,uint256)
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(steth);
        vm.expectRevert("ARM: Insufficient output amount");
        lidoARM.swapExactTokensForTokens(
            1, // amountIn
            1_000 ether, // amountOutMin
            path, // path
            address(this), // to
            block.timestamp // deadline
        );
    }

    function test_RevertWhen_SwapExactTokensForTokens_Because_InvalidePathLength() public {
        vm.expectRevert("ARM: Invalid path length");
        lidoARM.swapExactTokensForTokens(
            1, // amountIn
            1, // amountOutMin
            new address[](3), // path
            address(this), // to
            0 // deadline
        );
    }

    function test_RevertWhen_SwapExactTokensForTokens_Because_DeadlineExpired() public {
        vm.expectRevert("ARM: Deadline expired");
        lidoARM.swapExactTokensForTokens(
            1, // amountIn
            1, // amountOutMin
            new address[](2), // path
            address(this), // to
            block.timestamp - 1 // deadline
        );
    }

    /// @notice Test the following scenario:
    /// 1. Set steth balance of the ARM to 0.
    /// 2. Set weth balance of the ARM to MIN_TOTAL_SUPPLY.
    /// 3. Deposit DEFAULT_AMOUNT in the ARM.
    /// 4. Request redeem of DEFAULT_AMOUNT * 90%.
    /// 5. Try to swap DEFAULT_AMOUNT of stETH to WETH.
    function test_RevertWhen_SwapExactTokensForTokens_Because_InsufficientLiquidity_DueToRedeemRequest()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT * 10 + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        deal_(address(steth), address(lidoARM), 0)
        deal_(address(weth), address(lidoARM), MIN_TOTAL_SUPPLY)
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoARM(address(this), DEFAULT_AMOUNT * 90 / 100)
    {
        vm.expectRevert("ARM: Insufficient liquidity");
        lidoARM.swapExactTokensForTokens(
            steth, // inToken
            weth, // outToken
            DEFAULT_AMOUNT, // amountIn
            0, // amountOutMin
            address(this) // to
        );
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_SwapExactTokensForTokens_WithDeadLine_Weth_To_Steth() public {
        uint256 amountIn = 1 ether;
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(steth);

        // State before
        uint256 balanceWETHBeforeThis = weth.balanceOf(address(this));
        uint256 balanceSTETHBeforeThis = steth.balanceOf(address(this));
        uint256 balanceWETHBeforeARM = weth.balanceOf(address(lidoARM));
        uint256 balanceSTETHBeforeARM = steth.balanceOf(address(lidoARM));

        // Get minimum amount of stETH to receive
        uint256 traderates0 = lidoARM.traderate0();
        uint256 minAmount = amountIn * traderates0 / 1e36;

        // Expected events: Already checked in fuzz tests

        uint256[] memory outputs = new uint256[](2);
        // Main call
        outputs = lidoARM.swapExactTokensForTokens(
            amountIn, // amountIn
            minAmount, // amountOutMin
            path, // path
            address(this), // to
            block.timestamp // deadline
        );

        // State after
        uint256 balanceWETHAfterThis = weth.balanceOf(address(this));
        uint256 balanceSTETHAfterThis = steth.balanceOf(address(this));
        uint256 balanceWETHAfterARM = weth.balanceOf(address(lidoARM));
        uint256 balanceSTETHAfterARM = steth.balanceOf(address(lidoARM));

        // Assertions
        assertEq(balanceWETHBeforeThis, balanceWETHAfterThis + amountIn, "user WETH balance");
        assertApproxEqAbs(
            balanceSTETHBeforeThis + minAmount, balanceSTETHAfterThis, STETH_ERROR_ROUNDING, "user stETH balance"
        );
        assertEq(balanceWETHBeforeARM + amountIn, balanceWETHAfterARM, "ARM WETH balance");
        assertApproxEqAbs(
            balanceSTETHBeforeARM, balanceSTETHAfterARM + minAmount, STETH_ERROR_ROUNDING, "ARM stETH balance"
        );
        assertEq(outputs[0], amountIn, "amount in");
        assertEq(outputs[1], minAmount, "amount out");
    }

    function test_SwapExactTokensForTokens_WithDeadLine_Steth_To_Weth() public {
        uint256 amountIn = 1 ether;
        address[] memory path = new address[](2);
        path[0] = address(steth);
        path[1] = address(weth);

        // State before
        uint256 balanceWETHBeforeThis = weth.balanceOf(address(this));
        uint256 balanceSTETHBeforeThis = steth.balanceOf(address(this));
        uint256 balanceWETHBeforeARM = weth.balanceOf(address(lidoARM));
        uint256 balanceSTETHBeforeARM = steth.balanceOf(address(lidoARM));

        // Get minimum amount of WETH to receive
        uint256 traderates1 = lidoARM.traderate1();
        uint256 minAmount = amountIn * traderates1 / 1e36;

        // Expected events: Already checked in fuzz tests

        uint256[] memory outputs = new uint256[](2);
        // Main call
        outputs = lidoARM.swapExactTokensForTokens(
            amountIn, // amountIn
            minAmount, // amountOutMin
            path, // path
            address(this), // to
            block.timestamp // deadline
        );

        // State after
        uint256 balanceWETHAfterThis = weth.balanceOf(address(this));
        uint256 balanceSTETHAfterThis = steth.balanceOf(address(this));
        uint256 balanceWETHAfterARM = weth.balanceOf(address(lidoARM));
        uint256 balanceSTETHAfterARM = steth.balanceOf(address(lidoARM));

        // Assertions
        assertEq(balanceWETHBeforeThis + minAmount, balanceWETHAfterThis);
        assertApproxEqAbs(balanceSTETHBeforeThis, balanceSTETHAfterThis + amountIn, STETH_ERROR_ROUNDING);
        assertEq(balanceWETHBeforeARM, balanceWETHAfterARM + minAmount);
        assertApproxEqAbs(balanceSTETHBeforeARM + amountIn, balanceSTETHAfterARM, STETH_ERROR_ROUNDING);
        assertEq(outputs[0], amountIn);
        assertEq(outputs[1], minAmount);
    }

    /// @notice Test the following scenario:
    /// - Trader swap stETH for wETH
    /// - wETH ARM Balance > wETH swap out + outstanding withdrawals
    /// - wETH ARM Balance < wETH swap out + outstanding withdrawals + accrued fees
    function test_SwapExactTokensForTokens_StETH_To_WETH_When_WETHBalanceIsLowerThanSwapOutAndWithdrawalAndFees()
        public
        setLiquidityProviderCap(address(this), type(uint256).max)
        setTotalAssetsCap(type(uint256).max)
    {
        // Deposit to calculate fees
        lidoARM.deposit(DEFAULT_AMOUNT);

        // Estimated amount out
        uint256 amountIn = 500 ether;
        uint256 estimatedAmountOut = amountIn * lidoARM.traderate1() / lidoARM.PRICE_SCALE();

        uint256 balanceWETHBeforeARM = weth.balanceOf(address(lidoARM));
        uint256 feesAccrued = lidoARM.feesAccrued();
        // Increase lidoWithdrawalQueueAmount
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether + balanceWETHBeforeARM - feesAccrued - estimatedAmountOut;
        vm.prank(lidoARM.owner());
        lidoARM.requestStETHWithdrawalForETH(amounts);
        uint256 lidoWithdrawalQueueAmount = lidoARM.lidoWithdrawalQueueAmount();

        // Ensure test scenario is correct
        require(balanceWETHBeforeARM > estimatedAmountOut + lidoWithdrawalQueueAmount, "Balance too low");
        require(balanceWETHBeforeARM < estimatedAmountOut + lidoWithdrawalQueueAmount + feesAccrued, "Balance too high");

        // State before
        uint256 balanceWETHBeforeThis = weth.balanceOf(address(this));
        uint256 balanceSTETHBeforeThis = steth.balanceOf(address(this));
        uint256 balanceSTETHBeforeARM = steth.balanceOf(address(lidoARM));

        // Perfom swap
        lidoARM.swapExactTokensForTokens(
            steth, // inToken
            weth, // outToken
            amountIn, // amountIn
            0, // amountOutMin
            address(this) // to
        );

        // State after
        assertEq(weth.balanceOf(address(this)), balanceWETHBeforeThis + estimatedAmountOut, "user WETH balance");
        assertEq(weth.balanceOf(address(lidoARM)), balanceWETHBeforeARM - estimatedAmountOut, "ARM WETH balance");
        assertApproxEqAbs(
            steth.balanceOf(address(this)),
            balanceSTETHBeforeThis - amountIn,
            STETH_ERROR_ROUNDING,
            "user stETH balance"
        );
        assertApproxEqAbs(
            steth.balanceOf(address(lidoARM)),
            balanceSTETHBeforeARM + amountIn,
            STETH_ERROR_ROUNDING,
            "ARM stETH balance"
        );
    }

    //////////////////////////////////////////////////////
    /// --- FUZZING TESTS
    //////////////////////////////////////////////////////
    /// @notice Fuzz test for swapExactTokensForTokens(IERC20,IERC20,uint256,uint256,address), with WETH to stETH.
    /// @param amountIn Amount of WETH to swap. Fuzzed between 0 and steth in the ARM.
    /// @param stethReserve Amount of stETH in the ARM. Fuzzed between 0 and MAX_STETH_RESERVE.
    /// @param price Price of the stETH in WETH. Fuzzed between 0.98 and 1.
    function test_SwapExactTokensForTokens_Weth_To_Steth(uint256 amountIn, uint256 stethReserve, uint256 price)
        public
    {
        // Use random stETH/WETH sell price between 0.98 and 1,
        // the buy price doesn't matter as it is not used in this test.
        price = _bound(price, MIN_PRICE1, MAX_PRICE1);
        lidoARM.setPrices(MIN_PRICE0, price);

        // Set random amount of stETH in the ARM
        stethReserve = _bound(stethReserve, 0, MAX_STETH_RESERVE);
        deal(address(steth), address(lidoARM), stethReserve + (2 * STETH_ERROR_ROUNDING));

        // Calculate maximum amount of WETH to swap
        // It is ok to take 100% of the balance of stETH of the ARM as the price is below 1.
        amountIn = _bound(amountIn, 0, stethReserve);
        deal(address(weth), address(this), amountIn);

        // State before
        uint256 balanceWETHBeforeThis = weth.balanceOf(address(this));
        uint256 balanceSTETHBeforeThis = steth.balanceOf(address(this));
        uint256 balanceWETHBeforeARM = weth.balanceOf(address(lidoARM));
        uint256 balanceSTETHBeforeARM = steth.balanceOf(address(lidoARM));

        // Get minimum amount of stETH to receive
        // stETH = WETH / price
        uint256 amountOutMin =
            amountIn > STETH_ERROR_ROUNDING ? amountIn * 1e36 / price - STETH_ERROR_ROUNDING : amountIn * 1e36 / price;

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(this), address(lidoARM), amountIn);
        // TODO hard to get the exact amount of stETH transferred as it depends on the rounding
        // vm.expectEmit({emitter: address(steth)});
        // emit IERC20.Transfer(address(lidoARM), address(this), amountOutMin);

        // Main call
        lidoARM.swapExactTokensForTokens(
            weth, // inToken
            steth, // outToken
            amountIn, // amountIn
            amountOutMin, // amountOutMin
            address(this) // to
        );

        // State after
        uint256 balanceWETHAfterThis = weth.balanceOf(address(this));
        uint256 balanceSTETHAfterThis = steth.balanceOf(address(this));
        uint256 balanceWETHAfterARM = weth.balanceOf(address(lidoARM));
        uint256 balanceSTETHAfterARM = steth.balanceOf(address(lidoARM));

        // Assertions
        assertEq(balanceWETHBeforeThis, balanceWETHAfterThis + amountIn, "user WETH balance");
        assertApproxEqAbs(
            balanceSTETHBeforeThis + amountOutMin, balanceSTETHAfterThis, STETH_ERROR_ROUNDING * 2, "user stETH balance"
        );
        assertEq(balanceWETHBeforeARM + amountIn, balanceWETHAfterARM, "ARM WETH balance");
        assertApproxEqAbs(
            balanceSTETHBeforeARM, balanceSTETHAfterARM + amountOutMin, STETH_ERROR_ROUNDING * 2, "ARM stETH balance"
        );
    }

    /// @notice Fuzz test for swapExactTokensForTokens(IERC20,IERC20,uint256,uint256,address), with stETH to WETH.
    /// @param amountIn Amount of stETH to swap. Fuzzed between 0 and weth in the ARM.
    /// @param wethReserve Amount of WETH in the ARM. Fuzzed between 0 and MAX_WETH_RESERVE.
    /// @param price Price of the stETH in WETH. Fuzzed between 1 and 1.02.
    function test_SwapExactTokensForTokens_Steth_To_Weth(uint256 amountIn, uint256 wethReserve, uint256 price) public {
        // Use random stETH/WETH buy price between MIN_PRICE0 and MAX_PRICE0,
        // the sell price doesn't matter as it is not used in this test.
        price = _bound(price, MIN_PRICE0, MAX_PRICE0);
        lidoARM.setPrices(price, MAX_PRICE1);

        // Set random amount of WETH in the ARM
        wethReserve = _bound(wethReserve, 0, MAX_WETH_RESERVE);
        deal(address(weth), address(lidoARM), wethReserve);

        // Calculate maximum amount of stETH to swap
        // As the price is below 1, we can take 100% of the balance of WETH of the ARM.
        amountIn = _bound(amountIn, 0, wethReserve);
        deal(address(steth), address(this), amountIn);

        // State before
        uint256 balanceWETHBeforeThis = weth.balanceOf(address(this));
        uint256 balanceSTETHBeforeThis = steth.balanceOf(address(this));
        uint256 balanceWETHBeforeARM = weth.balanceOf(address(lidoARM));
        uint256 balanceSTETHBeforeARM = steth.balanceOf(address(lidoARM));

        // Get minimum amount of WETH to receive
        uint256 minAmount = amountIn * price / 1e36;

        // Expected events
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(address(this), address(lidoARM), amountIn);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoARM), address(this), minAmount);

        // Main call
        lidoARM.swapExactTokensForTokens(
            steth, // inToken
            weth, // outToken
            amountIn, // amountIn
            minAmount, // amountOutMin
            address(this) // to
        );

        // State after
        uint256 balanceWETHAfterThis = weth.balanceOf(address(this));
        uint256 balanceSTETHAfterThis = steth.balanceOf(address(this));
        uint256 balanceWETHAfterARM = weth.balanceOf(address(lidoARM));
        uint256 balanceSTETHAfterARM = steth.balanceOf(address(lidoARM));

        // Assertions
        assertEq(balanceWETHBeforeThis + minAmount, balanceWETHAfterThis, "user WETH balance");
        assertApproxEqAbs(
            balanceSTETHBeforeThis, balanceSTETHAfterThis + amountIn, STETH_ERROR_ROUNDING, "user stETH balance"
        );
        assertEq(balanceWETHBeforeARM, balanceWETHAfterARM + minAmount, "ARM WETH balance");
        assertApproxEqAbs(
            balanceSTETHBeforeARM + amountIn, balanceSTETHAfterARM, STETH_ERROR_ROUNDING, "ARM stETH balance"
        );
    }
}
