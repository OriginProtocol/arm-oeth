// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Test imports
import {Utils} from "./Utils.sol";
import {Setup} from "./Setup.sol";

abstract contract Properties is Setup, Utils {
    ////////////////////////////////////////////////////
    /// --- GHOSTS
    ////////////////////////////////////////////////////
    uint256 sum_weth_fees;
    uint256 sum_weth_swap_in;
    uint256 sum_weth_swap_out;
    uint256 sum_weth_deposit;
    uint256 sum_weth_withdraw;
    uint256 sum_weth_donated;
    uint256 sum_weth_lido_redeem;
    uint256 sum_steth_lido_requested;
    uint256 sum_steth_swap_out;
    uint256 sum_steth_swap_in;
    uint256 sum_steth_donated;
    bool ghost_swap_C = true;
    bool ghost_swap_D = true;

    ////////////////////////////////////////////////////
    /// --- SWAPS
    ////////////////////////////////////////////////////
    function property_swap_A() public view returns (bool) {
        uint256 inflows = sum_weth_deposit + sum_weth_swap_in + sum_weth_lido_redeem + sum_weth_donated;
        uint256 outflows = sum_weth_swap_out + sum_weth_withdraw + sum_weth_fees;

        return eq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + inflows - outflows);
    }

    function property_swap_B() public view returns (bool) {
        uint256 inflows = sum_steth_donated + sum_steth_swap_in;
        uint256 outflows = sum_steth_swap_out + sum_steth_lido_requested;

        return eq(steth.balanceOf(address(lidoARM)), inflows - outflows);
    }

    function property_swap_C() public view returns (bool) {
        return ghost_swap_C;
    }

    function property_swap_D() public view returns (bool) {
        return ghost_swap_D;
    }

    ////////////////////////////////////////////////////
    /// --- HELPERS
    ////////////////////////////////////////////////////
    function estimateAmountIn(IERC20 tokenOut, uint256 amountOut) public view returns (uint256) {
        return (amountOut * lidoARM.PRICE_SCALE()) / price(tokenOut == weth ? steth : weth) + 3;
    }

    function estimateAmountOut(IERC20 tokenIn, uint256 amountIn) public view returns (uint256) {
        return (amountIn * price(tokenIn)) / lidoARM.PRICE_SCALE();
    }

    function price(IERC20 token) public view returns (uint256) {
        return token == lidoARM.token0() ? lidoARM.traderate0() : lidoARM.traderate1();
    }
}
