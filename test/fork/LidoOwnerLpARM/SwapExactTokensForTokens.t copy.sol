// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

import {IERC20} from "contracts/Interfaces.sol";

contract Fork_Concrete_LidoOwnerLpARM_SwapExactTokensForTokens_Test_ is Fork_Shared_Test_ {
    // Account for stETH rounding errors.
    // See https://docs.lido.fi/guides/lido-tokens-integration-guide/#1-2-wei-corner-case
    uint256 constant ROUNDING = STETH_ERROR_ROUNDING;

    IERC20 BAD_TOKEN;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        deal(address(weth), address(lidoOwnerLpARM), 1_000_000 ether);
        deal(address(steth), address(lidoOwnerLpARM), 1_000_000 ether);

        BAD_TOKEN = IERC20(makeAddr("bad token"));
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_SwapExactTokensForTokens_Because_InvalidTokenIn() public {
        vm.expectRevert("ARM: Invalid token");
        lidoOwnerLpARM.swapExactTokensForTokens(BAD_TOKEN, steth, 10 ether, 0, address(this));
        vm.expectRevert("ARM: Invalid token");
        lidoOwnerLpARM.swapExactTokensForTokens(BAD_TOKEN, weth, 10 ether, 0, address(this));
        vm.expectRevert("ARM: Invalid token");
        lidoOwnerLpARM.swapExactTokensForTokens(weth, weth, 10 ether, 0, address(this));
        vm.expectRevert("ARM: Invalid token");
        lidoOwnerLpARM.swapExactTokensForTokens(steth, steth, 10 ether, 0, address(this));
    }

    function test_RevertWhen_SwapExactTokensForTokens_Because_InvalidTokenOut() public {
        vm.expectRevert("ARM: Invalid token");
        lidoOwnerLpARM.swapExactTokensForTokens(steth, BAD_TOKEN, 10 ether, 0, address(this));
        vm.expectRevert("ARM: Invalid token");
        lidoOwnerLpARM.swapExactTokensForTokens(weth, BAD_TOKEN, 10 ether, 0, address(this));
        vm.expectRevert("ARM: Invalid token");
        lidoOwnerLpARM.swapExactTokensForTokens(weth, weth, 10 ether, 0, address(this));
        vm.expectRevert("ARM: Invalid token");
        lidoOwnerLpARM.swapExactTokensForTokens(steth, steth, 10 ether, 0, address(this));
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_SwapExactTokensForTokens_WETH_TO_STETH() public {
        _swapExactTokensForTokens(weth, steth, 10 ether, 6.25 ether);
    }

    function test_SwapExactTokensForTokens_STETH_TO_WETH() public {
        _swapExactTokensForTokens(steth, weth, 10 ether, 5 ether);
    }

    function test_RealisticSwap() public {
        lidoOwnerLpARM.setPrices(997 * 1e33, 998 * 1e33);
        _swapExactTokensForTokens(steth, weth, 10 ether, 9.97 ether);
        _swapExactTokensForTokens(weth, steth, 10 ether, 10020040080160320641);
    }

    //////////////////////////////////////////////////////
    /// --- HELPERS
    //////////////////////////////////////////////////////
    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, uint256 expectedOut)
        internal
    {
        if (inToken == weth) {
            deal(address(weth), address(this), amountIn + 1000);
        } else {
            deal(address(steth), address(this), amountIn + 1000);
        }
        uint256 startIn = inToken.balanceOf(address(this));
        uint256 startOut = outToken.balanceOf(address(this));
        lidoOwnerLpARM.swapExactTokensForTokens(inToken, outToken, amountIn, 0, address(this));
        assertGt(inToken.balanceOf(address(this)), (startIn - amountIn) - ROUNDING, "In actual");
        assertLt(inToken.balanceOf(address(this)), (startIn - amountIn) + ROUNDING, "In actual");
        assertGe(outToken.balanceOf(address(this)), startOut + expectedOut - ROUNDING, "Out actual");
        assertLe(outToken.balanceOf(address(this)), startOut + expectedOut + ROUNDING, "Out actual");
    }
}
