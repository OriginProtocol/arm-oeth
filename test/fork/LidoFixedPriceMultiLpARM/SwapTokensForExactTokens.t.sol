// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

import {IERC20} from "contracts/Interfaces.sol";

contract Fork_Concrete_LidoARM_SwapTokensForExactTokens_Test is Fork_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////
    uint256 private constant MIN_PRICE0 = 980e33; // 0.98
    uint256 private constant MAX_PRICE0 = 1_000e33 - 1; // just under 1.00
    uint256 private constant MIN_PRICE1 = 1_000e33; // 1.00
    uint256 private constant MAX_PRICE1 = 1_020e33; // 1.02
    uint256 private constant INITIAL_BALANCE = 1_000 ether;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        deal(address(weth), address(this), INITIAL_BALANCE);
        deal(address(steth), address(this), INITIAL_BALANCE);

        deal(address(weth), address(lidoARM), INITIAL_BALANCE);
        deal(address(steth), address(lidoARM), INITIAL_BALANCE);

        // We are artificially adding assets so collect the performance fees to reset the fees collected
        lidoARM.collectFees();
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_SwapTokensForExactTokens_Because_InvalidTokenOut1() public {
        lidoARM.token0();
        vm.expectRevert("ARM: Invalid out token");
        lidoARM.swapTokensForExactTokens(
            steth, // inToken
            badToken, // outToken
            1, // amountOut
            1, // amountOutMax
            address(this) // to
        );
    }

    function test_RevertWhen_SwapTokensForExactTokens_Because_InvalidTokenOut0() public {
        vm.expectRevert("ARM: Invalid out token");
        lidoARM.swapTokensForExactTokens(
            weth, // inToken
            badToken, // outToken
            1, // amountOut
            1, // amountOutMax
            address(this) // to
        );
    }

    function test_RevertWhen_SwapTokensForExactTokens_Because_InvalidTokenIn() public {
        vm.expectRevert("ARM: Invalid in token");
        lidoARM.swapTokensForExactTokens(
            badToken, // inToken
            steth, // outToken
            1, // amountOut
            1, // amountOutMax
            address(this) // to
        );
    }

    function test_RevertWhen_SwapTokensForExactTokens_Because_BothInvalidTokens() public {
        vm.expectRevert("ARM: Invalid in token");
        lidoARM.swapTokensForExactTokens(
            badToken, // inToken
            badToken, // outToken
            1, // amountOut
            1, // amountOutMax
            address(this) // to
        );
    }

    function test_RevertWhen_SwapTokensForExactTokens_Because_NotEnoughTokenIn() public {
        deal(address(weth), address(this), 0);

        vm.expectRevert();
        lidoARM.swapTokensForExactTokens(
            weth, // inToken
            steth, // outToken
            1, // amountOut
            type(uint256).max, // amountOutMax
            address(this) // to
        );

        deal(address(steth), address(this), 0);
        vm.expectRevert();
        lidoARM.swapTokensForExactTokens(
            steth, // inToken
            weth, // outToken
            STETH_ERROR_ROUNDING + 1, // amountOut *
            type(uint256).max, // amountOutMax
            address(this) // to
        );
        // Note*: As deal can sometimes leave STETH_ERROR_ROUNDING to `to`, we need to try to transfer more.
    }

    function test_RevertWhen_SwapTokensForExactTokens_Because_NotEnoughTokenOut() public {
        deal(address(weth), address(this), 0);

        vm.expectRevert();
        lidoARM.swapTokensForExactTokens(
            weth, // inToken
            steth, // outToken
            1 ether, // amountOut
            type(uint256).max, // amountInMax
            address(this) // to
        );

        deal(address(steth), address(this), 0);
        vm.expectRevert("BALANCE_EXCEEDED"); // Lido error
        lidoARM.swapTokensForExactTokens(
            steth, // inToken
            weth, // outToken
            1 ether, // amountOut
            type(uint256).max, // amountInMax
            address(this) // to
        );
    }

    function test_RevertWhen_SwapTokensForExactTokens_Because_InsufficientOutputAmount() public {
        deal(address(steth), address(lidoARM), 100 wei);

        // Test for this function signature: swapTokensForExactTokens(IERC20,IERC20,uint56,uint256,address)
        vm.expectRevert("ARM: Excess input amount");
        lidoARM.swapTokensForExactTokens(
            weth, // inToken
            steth, // outToken
            1, // amountOut
            0, // amountInMax
            address(this) // to
        );

        // Test for this function signature: swapTokensForExactTokens(uint256,uint256,address[],address,uint256)
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(steth);
        vm.expectRevert("ARM: Excess input amount");
        lidoARM.swapTokensForExactTokens(
            1, // amountOut
            0, // amountInMax
            path, // path
            address(this), // to
            block.timestamp // deadline
        );
    }

    function test_RevertWhen_SwapTokensForExactTokens_Because_InvalidePathLength() public {
        vm.expectRevert("ARM: Invalid path length");
        lidoARM.swapTokensForExactTokens(
            1, // amountOut
            1, // amountInMax
            new address[](3), // path
            address(this), // to
            0 // deadline
        );
    }

    function test_RevertWhen_SwapTokensForExactTokens_Because_DeadlineExpired() public {
        vm.expectRevert("ARM: Deadline expired");
        lidoARM.swapTokensForExactTokens(
            1, // amountOut
            1, // amountInMax
            new address[](2), // path
            address(this), // to
            block.timestamp - 1 // deadline
        );
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_SwapTokensForExactTokens_WithDeadLine_Weth_To_Steth() public {
        uint256 amountOut = 1 ether;
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(steth);

        // State before
        uint256 balanceWETHBeforeThis = weth.balanceOf(address(this));
        uint256 balanceSTETHBeforeThis = steth.balanceOf(address(this));
        uint256 balanceWETHBeforeARM = weth.balanceOf(address(lidoARM));
        uint256 balanceSTETHBeforeARM = steth.balanceOf(address(lidoARM));

        // Get maximum amount of WETH to send to the ARM
        uint256 traderates0 = lidoARM.traderate0();
        uint256 amountIn = (amountOut * 1e36 / traderates0) + 3;

        // Expected events: Already checked in fuzz tests

        uint256[] memory outputs = new uint256[](2);
        // Main call
        outputs = lidoARM.swapTokensForExactTokens(
            amountOut, // amountOut
            amountIn, // amountInMax
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
        assertEq(balanceWETHBeforeThis, balanceWETHAfterThis + amountIn, "WETH user balance");
        assertApproxEqAbs(
            balanceSTETHBeforeThis + amountOut, balanceSTETHAfterThis, STETH_ERROR_ROUNDING, "STETH user balance"
        );
        assertEq(balanceWETHBeforeARM + amountIn, balanceWETHAfterARM, "WETH ARM balance");
        assertApproxEqAbs(
            balanceSTETHBeforeARM, balanceSTETHAfterARM + amountOut, STETH_ERROR_ROUNDING, "STETH ARM balance"
        );
        assertEq(outputs[0], amountIn, "Amount in");
        assertEq(outputs[1], amountOut, "Amount out");
    }

    function test_SwapTokensForExactTokens_WithDeadLine_Steth_To_Weth() public {
        uint256 amountOut = 1 ether;
        address[] memory path = new address[](2);
        path[0] = address(steth);
        path[1] = address(weth);

        // State before
        uint256 balanceWETHBeforeThis = weth.balanceOf(address(this));
        uint256 balanceSTETHBeforeThis = steth.balanceOf(address(this));
        uint256 balanceWETHBeforeARM = weth.balanceOf(address(lidoARM));
        uint256 balanceSTETHBeforeARM = steth.balanceOf(address(lidoARM));

        // Get maximum amount of stETH to send to the ARM
        uint256 traderates1 = lidoARM.traderate1();
        uint256 amountIn = (amountOut * 1e36 / traderates1) + 3;

        // Expected events: Already checked in fuzz tests

        uint256[] memory outputs = new uint256[](2);
        // Main call
        outputs = lidoARM.swapTokensForExactTokens(
            amountOut, // amountOut
            amountIn, // amountInMax
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
        assertEq(balanceWETHBeforeThis + amountOut, balanceWETHAfterThis, "WETH user balance");
        assertApproxEqAbs(
            balanceSTETHBeforeThis, balanceSTETHAfterThis + amountIn, STETH_ERROR_ROUNDING, "STETH user balance"
        );
        assertEq(balanceWETHBeforeARM, balanceWETHAfterARM + amountOut, "WETH ARM balance");
        assertApproxEqAbs(
            balanceSTETHBeforeARM + amountIn, balanceSTETHAfterARM, STETH_ERROR_ROUNDING, "STETH ARM balance"
        );
        assertEq(outputs[0], amountIn, "Amount in");
        assertEq(outputs[1], amountOut, "Amount out");
    }

    //////////////////////////////////////////////////////
    /// --- FUZZING TESTS
    //////////////////////////////////////////////////////
    /// @notice Fuzz test for swapTokensForExactTokens(IERC20,IERC20,uint256,uint256,address), with WETH to stETH.
    /// @param amountOut Exact amount of stETH to swap out of the ARM. Fuzzed between 0 and stETH in the ARM.
    /// @param wethReserveGrowth The amount WETH has grown in the ARM. Fuzzed between 0 and 1% of the INITIAL_BALANCE.
    /// @param stethReserveGrowth Amount of stETH has grown in the ARM. Fuzzed between 0 and 1% of the INITIAL_BALANCE.
    /// @param price Sell price of the stETH in WETH (stETH/WETH). Fuzzed between 1 and 1.02.
    /// @param collectFees Whether to collect the accrued performance fees before the swap.
    function test_SwapTokensForExactTokens_Weth_To_Steth(
        uint256 amountOut,
        uint256 wethReserveGrowth,
        uint256 stethReserveGrowth,
        uint256 price,
        uint256 collectFees
    ) public {
        // Use random sell price between 1 and 1.02 for the stETH/WETH price,
        // The buy price doesn't matter as it is not used in this test.
        price = _bound(price, MIN_PRICE1, MAX_PRICE1);
        lidoARM.setPrices(MIN_PRICE0, price);

        // Set random amount of WETH in the ARM
        wethReserveGrowth = _bound(wethReserveGrowth, 0, INITIAL_BALANCE / 100);
        deal(address(weth), address(lidoARM), INITIAL_BALANCE + wethReserveGrowth);

        // Set random amount of stETH in the ARM
        stethReserveGrowth = _bound(stethReserveGrowth, 0, INITIAL_BALANCE / 100);
        deal(address(steth), address(lidoARM), INITIAL_BALANCE + stethReserveGrowth);

        collectFees = bound(collectFees, 0, 1);
        if (collectFees == 1) {
            // Collect and accrued performance fees before the swap
            lidoARM.collectFees();
        }

        // Calculate the amount of stETH to swap out of the ARM
        amountOut = _bound(amountOut, 0, steth.balanceOf(address(lidoARM)));

        // Get the maximum amount of WETH to swap into the ARM
        // weth = steth * stETH/WETH price
        uint256 amountIn = (amountOut * price / 1e36) + 3;

        deal(address(weth), address(this), amountIn);

        // State before
        uint256 totalAssetsBefore = lidoARM.totalAssets();
        uint256 balanceWETHBeforeThis = weth.balanceOf(address(this));
        uint256 balanceSTETHBeforeThis = steth.balanceOf(address(this));
        uint256 balanceWETHBeforeARM = weth.balanceOf(address(lidoARM));
        uint256 balanceSTETHBeforeARM = steth.balanceOf(address(lidoARM));

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(this), address(lidoARM), amountIn);
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(address(lidoARM), address(this), amountOut);

        // Main call
        lidoARM.swapTokensForExactTokens(
            weth, // inToken
            steth, // outToken
            amountOut, // amountOut
            amountIn, // amountInMax
            address(this) // to
        );

        // Assertions
        assertGe(lidoARM.totalAssets(), totalAssetsBefore, "total assets after");
        assertEq(weth.balanceOf(address(this)), balanceWETHBeforeThis - amountIn, "WETH user balance");
        assertApproxEqAbs(
            steth.balanceOf(address(this)),
            balanceSTETHBeforeThis + amountOut,
            STETH_ERROR_ROUNDING,
            "STETH user balance"
        );
        assertEq(weth.balanceOf(address(lidoARM)), balanceWETHBeforeARM + amountIn, "WETH ARM balance");
        assertApproxEqAbs(
            steth.balanceOf(address(lidoARM)),
            balanceSTETHBeforeARM - amountOut,
            STETH_ERROR_ROUNDING,
            "STETH ARM balance"
        );
    }

    /// @notice Fuzz test for swapTokensForExactTokens(IERC20,IERC20,uint256,uint256,address), with stETH to WETH.
    /// @param amountOut Exact amount of WETH to swap out of the ARM. Fuzzed between 0 and WETH in the ARM.
    /// @param wethReserveGrowth The amount WETH has grown in the ARM. Fuzzed between 0 and 1% of the INITIAL_BALANCE.
    /// @param stethReserveGrowth Amount of stETH has grown in the ARM. Fuzzed between 0 and 1% of the INITIAL_BALANCE.
    /// @param price Buy price of the stETH in WETH (stETH/WETH). Fuzzed between 0.998 and 1.02.
    /// @param userStethBalance The amount of stETH the user has before the swap.
    /// @param collectFees Whether to collect the accrued performance fees before the swap.
    function test_SwapTokensForExactTokens_Steth_To_Weth(
        uint256 amountOut,
        uint256 wethReserveGrowth,
        uint256 stethReserveGrowth,
        uint256 price,
        uint256 userStethBalance,
        uint256 collectFees
    ) public {
        lidoARM.collectFees();

        // Use random stETH/WETH buy price between 0.98 and 1,
        // sell price doesn't matter as it is not used in this test.
        price = _bound(price, MIN_PRICE0, MAX_PRICE0);
        lidoARM.setPrices(price, MAX_PRICE1);

        // Set random amount of WETH growth in the ARM
        wethReserveGrowth = _bound(wethReserveGrowth, 0, INITIAL_BALANCE / 100);
        deal(address(weth), address(lidoARM), INITIAL_BALANCE + wethReserveGrowth);

        // Set random amount of stETH growth in the ARM
        stethReserveGrowth = _bound(stethReserveGrowth, 0, INITIAL_BALANCE / 100);
        deal(address(steth), address(lidoARM), INITIAL_BALANCE + stethReserveGrowth);

        collectFees = bound(collectFees, 0, 1);
        if (collectFees == 1) {
            // Collect and accrued performance fees before the swap
            lidoARM.collectFees();
        }

        // Calculate the amount of WETH to swap out of the ARM
        // Can take up to 100% of the WETH in the ARM even if there is some for the performance fee.
        amountOut = _bound(amountOut, 0, weth.balanceOf(address(lidoARM)));
        // Get the maximum amount of stETH to swap into of the ARM
        // stETH = WETH / stETH/WETH price
        uint256 amountIn = (amountOut * 1e36 / price) + 3;

        // Fuzz the user's stETH balance
        userStethBalance = _bound(userStethBalance, amountIn, amountIn + 1 ether);
        deal(address(steth), address(this), userStethBalance);

        // State before
        uint256 totalAssetsBefore = lidoARM.totalAssets();
        uint256 balanceWETHBeforeThis = weth.balanceOf(address(this));
        uint256 balanceSTETHBeforeThis = steth.balanceOf(address(this));
        uint256 balanceWETHBeforeARM = weth.balanceOf(address(lidoARM));
        uint256 balanceSTETHBeforeARM = steth.balanceOf(address(lidoARM));

        // Expected events
        // TODO hard to check the exact amount of stETH due to rounding
        // vm.expectEmit({emitter: address(steth)});
        // emit IERC20.Transfer(address(this), address(lidoARM), amountIn);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoARM), address(this), amountOut);

        // Main call
        lidoARM.swapTokensForExactTokens(
            steth, // inToken
            weth, // outToken
            amountOut, // amountOut
            amountIn + 2 * STETH_ERROR_ROUNDING, // amountInMax
            address(this) // to
        );

        // Assertions
        assertGe(lidoARM.totalAssets(), totalAssetsBefore, "total assets after");
        assertEq(weth.balanceOf(address(this)), balanceWETHBeforeThis + amountOut, "WETH user balance");
        assertApproxEqAbs(
            steth.balanceOf(address(this)),
            balanceSTETHBeforeThis - amountIn,
            STETH_ERROR_ROUNDING,
            "STETH user balance"
        );
        assertEq(weth.balanceOf(address(lidoARM)), balanceWETHBeforeARM - amountOut, "WETH ARM balance");
        assertApproxEqAbs(
            steth.balanceOf(address(lidoARM)),
            balanceSTETHBeforeARM + amountIn,
            STETH_ERROR_ROUNDING,
            "STETH ARM balance"
        );
    }

    /// @notice If the buy and sell prices are very close together and the stETH transferred into
    /// the ARM is truncated, then there should be enough rounding protection against losing total assets.
    function test_SwapTokensForExactTokens_Steth_Transfer_Truncated()
        public
        disableCaps
        setArmBalances(MIN_TOTAL_SUPPLY, 0)
        setPrices(1e36 - 1, 1e36, 1e36)
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
    {
        // The exact amount of WETH to receive
        uint256 amountOut = DEFAULT_AMOUNT;
        // The max amount of stETH to send
        uint256 amountInMax = amountOut + 3;
        deal(address(steth), address(this), amountInMax); // Deal more as AmountIn is greater than AmountOut

        // State before
        uint256 totalAssetsBefore = lidoARM.totalAssets();

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoARM), address(this), amountOut);

        // Main call
        lidoARM.swapTokensForExactTokens(
            steth, // inToken
            weth, // outToken
            amountOut, // amountOut
            amountInMax, // amountInMax
            address(this) // to
        );

        // Assertions
        assertGe(lidoARM.totalAssets(), totalAssetsBefore, "total assets after");
    }
}
