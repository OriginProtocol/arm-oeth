// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {console} from "forge-std/Console.sol";

// Handlers
import {BaseHandler} from "./BaseHandler.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {LidoARM} from "contracts/LidoARM.sol";

/// @notice SwapHandler contract
/// @dev This contract is used to handle all functionnalities related to the swap in the ARM.
contract SwapHandler is BaseHandler {
    ////////////////////////////////////////////////////
    /// --- CONSTANTS && IMMUTABLES
    ////////////////////////////////////////////////////
    IERC20 public immutable weth;
    IERC20 public immutable steth;
    LidoARM public immutable arm;

    ////////////////////////////////////////////////////
    /// --- VARIABLES
    ////////////////////////////////////////////////////
    address[] public swaps; // Users that perform swap

    ////////////////////////////////////////////////////
    /// --- VARIABLES FOR INVARIANT ASSERTIONS
    ////////////////////////////////////////////////////
    uint256 public sum_of_weth_in;
    uint256 public sum_of_weth_out;
    uint256 public sum_of_steth_in;
    uint256 public sum_of_steth_out;

    ////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ////////////////////////////////////////////////////
    constructor(address _arm, address _weth, address _steth, address[] memory _swaps) {
        arm = LidoARM(payable(_arm));
        weth = IERC20(_weth);
        steth = IERC20(_steth);

        require(_swaps.length > 0, "SH: EMPTY_SWAPS");
        swaps = _swaps;

        names[address(weth)] = "WETH";
        names[address(steth)] = "STETH";
    }

    ////////////////////////////////////////////////////
    /// --- ACTIONS
    ////////////////////////////////////////////////////
    function swapExactTokensForTokens(uint256 _seed) external {
        numberOfCalls["swapHandler.swapExactTokens"]++;

        // Select a random user
        address user;
        uint256 len = swaps.length;
        uint256 __seed = _bound(_seed, 0, type(uint256).max - len);
        for (uint256 i; i < len; i++) {
            user = swaps[(__seed + i) % len];
            if (weth.balanceOf(user) > 0 || steth.balanceOf(user) > 0) break;
        }

        // Select an input token and build path
        IERC20 inputToken = _seed % 2 == 0 ? weth : steth;
        IERC20 outputToken = inputToken == weth ? steth : weth;
        address[] memory path = new address[](2);
        path[0] = address(inputToken);
        path[1] = address(outputToken);

        // Select a random amount, maximum is the minimum between the balance of the user and the liquidity available
        uint256 amount = _bound(_seed, 0, min(inputToken.balanceOf(user), getMaxAmountOut(inputToken)));
        if (inputToken == weth && amount <= 2 && steth.balanceOf(address(arm)) < 2) {
            numberOfCalls["swapHandler.swapExactTokens.skip"]++;
            console.log("LpHandler.swapExactTokens - Not enough stETH in the ARM");
            return;
        }
        console.log(
            "swapHandler.swapExactTokensForTokens(%18e), %s, %s", amount, names[user], names[address(inputToken)]
        );

        // Prank user
        vm.startPrank(user);

        // Approve the ARM to spend the input token
        inputToken.approve(address(arm), amount);

        // Swap
        // Note: this implementation is prefered as it returns the amount of output tokens
        uint256[] memory amounts = arm.swapExactTokensForTokens({
            amountIn: amount,
            amountOutMin: 0,
            path: path,
            to: address(user),
            deadline: block.timestamp + 1
        });

        // End prank
        vm.stopPrank();

        // Update sum of swaps
        if (inputToken == weth) {
            sum_of_weth_in += amount;
            sum_of_steth_out += amounts[1];
        } else {
            sum_of_steth_in += amount;
            sum_of_weth_out += amounts[1];
        }
    }

    ////////////////////////////////////////////////////
    /// --- HELPERS
    ////////////////////////////////////////////////////
    function getMaxAmountOut(IERC20 tokenIn) public view returns (uint256) {
        IERC20 tokenOut = tokenIn == weth ? steth : weth;

        // Todo: need to take into account withdraw queue for wETH
        uint256 reserveOut = tokenOut.balanceOf(address(arm));

        uint256 price = tokenIn == steth ? arm.traderate0() : arm.traderate1();

        return (reserveOut * arm.PRICE_SCALE()) / price;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
