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

        // Get minimum amount of STETH to receive
        uint256 traderates1 = lidoARM.traderate1();
        uint256 amountIn = (amountOut * 1e36 / traderates1) + 1;

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
        assertEq(balanceWETHBeforeThis, balanceWETHAfterThis + amountIn);
        assertApproxEqAbs(balanceSTETHBeforeThis + amountOut, balanceSTETHAfterThis, STETH_ERROR_ROUNDING);
        assertEq(balanceWETHBeforeARM + amountIn, balanceWETHAfterARM);
        assertApproxEqAbs(balanceSTETHBeforeARM, balanceSTETHAfterARM + amountOut, STETH_ERROR_ROUNDING);
        assertEq(outputs[0], amountIn);
        assertEq(outputs[1], amountOut);
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

        // Get minimum amount of WETH to receive
        uint256 traderates0 = lidoARM.traderate0();
        uint256 amountIn = (amountOut * 1e36 / traderates0) + 1;

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
        assertEq(balanceWETHBeforeThis + amountOut, balanceWETHAfterThis);
        assertApproxEqAbs(balanceSTETHBeforeThis, balanceSTETHAfterThis + amountIn, STETH_ERROR_ROUNDING);
        assertEq(balanceWETHBeforeARM, balanceWETHAfterARM + amountOut);
        assertApproxEqAbs(balanceSTETHBeforeARM + amountIn, balanceSTETHAfterARM, STETH_ERROR_ROUNDING);
        assertEq(outputs[0], amountIn);
        assertEq(outputs[1], amountOut);
    }

    //////////////////////////////////////////////////////
    /// --- FUZZING TESTS
    //////////////////////////////////////////////////////
    /// @notice Fuzz test for swapTokensForExactTokens(IERC20,IERC20,uint256,uint256,address), with WETH to stETH.
    /// @param amountOut Amount of WETH to swap. Fuzzed between 0 and steth in the ARM.
    /// @param stethReserve Amount of stETH in the ARM. Fuzzed between 0 and MAX_STETH_RESERVE.
    /// @param price Price of the stETH in WETH. Fuzzed between 0.98 and 1.
    function test_SwapTokensForExactTokens_Weth_To_Steth(uint256 amountOut, uint256 stethReserve, uint256 price)
        public
    {
        // Use random price between 0.98 and 1 for traderate1,
        // Traderate0 value doesn't matter as it is not used in this test.
        price = _bound(price, MIN_PRICE0, MAX_PRICE0);
        lidoARM.setPrices(price, MAX_PRICE1);

        // Set random amount of stETH in the ARM
        stethReserve = _bound(stethReserve, 0, MAX_STETH_RESERVE);
        deal(address(steth), address(lidoARM), stethReserve);

        // Calculate maximum amount of WETH to swap
        // It is ok to take 100% of the balance of stETH of the ARM as the price is below 1.
        amountOut = _bound(amountOut, 0, stethReserve);
        deal(address(weth), address(this), amountOut * 2 + 1); // // Deal more as AmountIn is greater than AmountOut

        // State before
        uint256 balanceWETHBeforeThis = weth.balanceOf(address(this));
        uint256 balanceSTETHBeforeThis = steth.balanceOf(address(this));
        uint256 balanceWETHBeforeARM = weth.balanceOf(address(lidoARM));
        uint256 balanceSTETHBeforeARM = steth.balanceOf(address(lidoARM));

        // Get minimum amount of STETH to receive
        uint256 traderates1 = lidoARM.traderate1();
        uint256 amountIn = (amountOut * 1e36 / traderates1) + 1;

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(this), address(lidoARM), amountIn);
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(address(lidoARM), address(this), amountOut + STETH_ERROR_ROUNDING);
        // Main call
        lidoARM.swapTokensForExactTokens(
            weth, // inToken
            steth, // outToken
            amountOut, // amountOut
            amountIn, // amountInMax
            address(this) // to
        );

        // State after
        uint256 balanceWETHAfterThis = weth.balanceOf(address(this));
        uint256 balanceSTETHAfterThis = steth.balanceOf(address(this));
        uint256 balanceWETHAfterARM = weth.balanceOf(address(lidoARM));
        uint256 balanceSTETHAfterARM = steth.balanceOf(address(lidoARM));

        // Assertions
        assertEq(balanceWETHBeforeThis, balanceWETHAfterThis + amountIn);
        assertApproxEqAbs(balanceSTETHBeforeThis + amountOut, balanceSTETHAfterThis, STETH_ERROR_ROUNDING);
        assertEq(balanceWETHBeforeARM + amountIn, balanceWETHAfterARM);
        assertApproxEqAbs(balanceSTETHBeforeARM, balanceSTETHAfterARM + amountOut, STETH_ERROR_ROUNDING);
    }

    /// @notice Fuzz test for swapTokensForExactTokens(IERC20,IERC20,uint256,uint256,address), with stETH to WETH.
    /// @param amountOut Amount of stETH to swap. Fuzzed between 0 and weth in the ARM.
    /// @param wethReserve Amount of WETH in the ARM. Fuzzed between 0 and MAX_WETH_RESERVE.
    /// @param price Price of the stETH in WETH. Fuzzed between 1 and 1.02.
    function test_SwapTokensForExactTokens_Steth_To_Weth(uint256 amountOut, uint256 wethReserve, uint256 price)
        public
    {
        // Use random price between MIN_PRICE1 and MAX_PRICE1 for traderate1,
        // Traderate0 value doesn't matter as it is not used in this test.
        price = _bound(price, MIN_PRICE1, MAX_PRICE1);
        lidoARM.setPrices(MIN_PRICE0, price);

        // Set random amount of WETH in the ARM
        wethReserve = _bound(wethReserve, 0, MAX_WETH_RESERVE);
        deal(address(weth), address(lidoARM), wethReserve);

        // Calculate maximum amount of stETH to swap
        // As the price is below 1, we can take 100% of the balance of WETH of the ARM.
        amountOut = _bound(amountOut, 0, wethReserve);
        deal(address(steth), address(this), amountOut * 2 + 1); // Deal more as AmountIn is greater than AmountOut

        // State before
        uint256 balanceWETHBeforeThis = weth.balanceOf(address(this));
        uint256 balanceSTETHBeforeThis = steth.balanceOf(address(this));
        uint256 balanceWETHBeforeARM = weth.balanceOf(address(lidoARM));
        uint256 balanceSTETHBeforeARM = steth.balanceOf(address(lidoARM));

        // Get minimum amount of WETH to receive
        uint256 traderates0 = lidoARM.traderate0();
        uint256 amountIn = (amountOut * 1e36 / traderates0) + 1;

        // Expected events
        vm.expectEmit({emitter: address(steth)});
        emit IERC20.Transfer(address(this), address(lidoARM), amountIn);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoARM), address(this), amountOut);

        // Main call
        lidoARM.swapTokensForExactTokens(
            steth, // inToken
            weth, // outToken
            amountOut, // amountOut
            amountIn, // amountInMax
            address(this) // to
        );

        // State after
        uint256 balanceWETHAfterThis = weth.balanceOf(address(this));
        uint256 balanceSTETHAfterThis = steth.balanceOf(address(this));
        uint256 balanceWETHAfterARM = weth.balanceOf(address(lidoARM));
        uint256 balanceSTETHAfterARM = steth.balanceOf(address(lidoARM));

        // Assertions
        assertEq(balanceWETHBeforeThis + amountOut, balanceWETHAfterThis);
        assertApproxEqAbs(balanceSTETHBeforeThis, balanceSTETHAfterThis + amountIn, STETH_ERROR_ROUNDING);
        assertEq(balanceWETHBeforeARM, balanceWETHAfterARM + amountOut);
        assertApproxEqAbs(balanceSTETHBeforeARM + amountIn, balanceSTETHAfterARM, STETH_ERROR_ROUNDING);
    }
}
