// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

import {IERC20} from "contracts/Interfaces.sol";

contract Fork_Concrete_LidoOwnerLpARM_SwapTokensForExactTokens_Test_ is Fork_Shared_Test_ {
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
    function test_RevertWhen_SwapTokensForExactTokens_Because_InvalidTokenIn() public {
        vm.expectRevert("ARM: Invalid token");
        lidoOwnerLpARM.swapTokensForExactTokens(BAD_TOKEN, steth, 10 ether, 0, address(this));
        vm.expectRevert("ARM: Invalid token");
        lidoOwnerLpARM.swapTokensForExactTokens(BAD_TOKEN, weth, 10 ether, 0, address(this));
        vm.expectRevert("ARM: Invalid token");
        lidoOwnerLpARM.swapTokensForExactTokens(weth, weth, 10 ether, 0, address(this));
        vm.expectRevert("ARM: Invalid token");
        lidoOwnerLpARM.swapTokensForExactTokens(steth, steth, 10 ether, 0, address(this));
    }

    function test_RevertWhen_SwapTokensForExactTokens_Because_InvalidTokenOut() public {
        vm.expectRevert("ARM: Invalid token");
        lidoOwnerLpARM.swapTokensForExactTokens(steth, BAD_TOKEN, 10 ether, 0, address(this));
        vm.expectRevert("ARM: Invalid token");
        lidoOwnerLpARM.swapTokensForExactTokens(weth, BAD_TOKEN, 10 ether, 0, address(this));
        vm.expectRevert("ARM: Invalid token");
        lidoOwnerLpARM.swapTokensForExactTokens(weth, weth, 10 ether, 0, address(this));
        vm.expectRevert("ARM: Invalid token");
        lidoOwnerLpARM.swapTokensForExactTokens(steth, steth, 10 ether, 0, address(this));
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_SwapTokensForExactTokens_WETH_TO_STETH() public {
        _swapTokensForExactTokens(weth, steth, 10 ether, 6.25 ether);
    }

    function test_SwapTokensForExactTokens_STETH_TO_WETH() public {
        _swapTokensForExactTokens(steth, weth, 10 ether, 5 ether);
    }

    //////////////////////////////////////////////////////
    /// --- HELPERS
    //////////////////////////////////////////////////////
    function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, uint256 expectedOut)
        internal
    {
        if (inToken == weth) {
            deal(address(weth), address(this), amountIn + 1000);
        } else {
            deal(address(steth), address(this), amountIn + 1000);
        }
        uint256 startIn = inToken.balanceOf(address(this));
        lidoOwnerLpARM.swapTokensForExactTokens(inToken, outToken, expectedOut, 3 * expectedOut, address(this));
        assertGt(inToken.balanceOf(address(this)), (startIn - amountIn) - ROUNDING, "In actual");
        assertLt(inToken.balanceOf(address(this)), (startIn - amountIn) + ROUNDING, "In actual");
        assertGe(outToken.balanceOf(address(this)), expectedOut - ROUNDING, "Out actual");
        assertLe(outToken.balanceOf(address(this)), expectedOut + ROUNDING, "Out actual");
    }
}
