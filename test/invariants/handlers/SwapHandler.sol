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
        uint256 amountIn = _bound(_seed, 0, min(inputToken.balanceOf(user), getMaxAmountOut(inputToken)));

        // Prevent swap when no liquidity on steth, but it will try to transfer the +2 stETH.
        if (inputToken == weth && amountIn <= 2 && steth.balanceOf(address(arm)) < 2) {
            numberOfCalls["swapHandler.swapExactTokens.skip"]++;
            console.log("SwapHandler.swapExactTokens - Not enough stETH in the ARM");
            return;
        }

        console.log(
            "SwapHandler.swapExactTokensForTokens(%18e), %s, %s", amountIn, names[user], names[address(inputToken)]
        );

        // Prank user
        vm.startPrank(user);

        // Approve the ARM to spend the input token
        inputToken.approve(address(arm), amountIn);

        // Swap
        // Note: this implementation is prefered as it returns the amountIn of output tokens
        uint256[] memory amounts = arm.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            path: path,
            to: address(user),
            deadline: block.timestamp + 1
        });

        // End prank
        vm.stopPrank();

        // Update sum of swaps
        if (inputToken == weth) {
            sum_of_weth_in += amountIn;
            sum_of_steth_out += amounts[1];
        } else {
            sum_of_steth_in += amountIn;
            sum_of_weth_out += amounts[1];
        }
    }

    function swapTokensForExactTokens(uint256 _seed) external {
        numberOfCalls["swapHandler.swapTokensExact"]++;

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
        uint256 amountOut =
            _bound(_seed, 0, min(outputToken.balanceOf(address(arm)), getMaxAmountIn(outputToken, user)));

        // Prevent swap when no liquidity on steth, but it will try to transfer the +2 stETH.
        if (inputToken == weth && amountOut <= 2 && steth.balanceOf(address(arm)) < 2) {
            numberOfCalls["swapHandler.swapTokensExact.skip"]++;
            console.log("SwapHandler.swapTokensForExactTokens - Not enough stETH in the ARM");
            return;
        }
        console.log(
            "SwapHandler.swapTokensForExactTokens(%18e), %s, %s", amountOut, names[user], names[address(inputToken)]
        );

        // Prank user
        vm.startPrank(user);

        // Approve the ARM to spend the input token
        // Approve max, to avoid calculating the exact amount
        inputToken.approve(address(arm), type(uint256).max);

        // Swap
        // Note: this implementation is prefered as it returns the amountIn of output tokens
        uint256[] memory amounts = arm.swapTokensForExactTokens({
            amountOut: amountOut,
            amountInMax: type(uint256).max,
            path: path,
            to: address(user),
            deadline: block.timestamp + 1
        });

        // End prank
        vm.stopPrank();

        // Update sum of swaps
        if (inputToken == weth) {
            sum_of_weth_out += amountOut;
            sum_of_steth_in += amounts[0];
        } else {
            sum_of_steth_out += amountOut;
            sum_of_weth_in += amounts[0];
        }
    }

    ////////////////////////////////////////////////////
    /// --- HELPERS
    ////////////////////////////////////////////////////
    /// @notice Helpers to calcul the maximum amount of token that we can use as input
    /// @dev Useful for swapExactTokensForTokens
    function getMaxAmountOut(IERC20 tokenIn) public view returns (uint256) {
        IERC20 tokenOut = tokenIn == weth ? steth : weth;

        // Todo: need to take into account withdraw queue for wETH
        uint256 reserveOut = tokenOut.balanceOf(address(arm));

        uint256 price = tokenIn == steth ? arm.traderate0() : arm.traderate1();

        return (reserveOut * arm.PRICE_SCALE()) / price;
    }

    /// @notice Helpers to calcul the maximum amount of token that we can use as input
    /// @dev Useful for swapTokensForExactTokens
    function getMaxAmountIn(IERC20 tokenOut, address user) public view returns (uint256) {
        IERC20 tokenIn = tokenOut == weth ? steth : weth;

        uint256 reserveUser = tokenIn.balanceOf(user);

        uint256 price = tokenIn == steth ? arm.traderate0() : arm.traderate1();

        return (reserveUser * arm.PRICE_SCALE()) / price + 1;
    }

    /// @notice Return the minimum between two uint256
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
