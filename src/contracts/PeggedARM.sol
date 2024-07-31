// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableOperable} from "./OwnableOperable.sol";
import {IERC20} from "./Interfaces.sol";

contract PeggedARM is OwnableOperable {
    // Uniswap V2 Router compatible interface to identify the pool pair
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    constructor(address _token0, address _token1) {
        require(IERC20(_token0).decimals() == 18);
        require(IERC20(_token1).decimals() == 18);

        token0 = IERC20(_token0);
        token1 = IERC20(_token1);

        _setOwner(address(0)); // Revoke owner for implementation contract at deployment
    }

    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible.
     * msg.sender should have already given the ARM contract an allowance of
     * at least amountIn on the input token.
     *
     * @param inToken Input token.
     * @param outToken Output token.
     * @param amountIn The amount of input tokens to send.
     * @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
     * @param to Recipient of the output tokens.
     */
    function swapExactTokensForTokens(
        IERC20 inToken,
        IERC20 outToken,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external {
        require(amountIn >= amountOutMin, "ARM: Insufficient output amount");
        _swap(inToken, outToken, amountIn, to);
    }

    /**
     * @notice Uniswap V2 Router compatible interface. Swaps an exact amount of
     * input tokens for as many output tokens as possible.
     * msg.sender should have already given the ARM contract an allowance of
     * at least amountIn on the input token.
     *
     * @param amountIn The amount of input tokens to send.
     * @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
     * @param path The input and output token addresses.
     * @param to Recipient of the output tokens.
     * @param deadline Unix timestamp after which the transaction will revert.
     * @return amounts The input and output token amounts.
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(amountIn >= amountOutMin, "ARM: Insufficient output amount");
        require(path.length == 2, "ARM: Invalid path length");
        _inDeadline(deadline);

        IERC20 inToken = IERC20(path[0]);
        IERC20 outToken = IERC20(path[1]);

        _swap(inToken, outToken, amountIn, to);

        // Swaps are 1:1 so the input amount is the output amount
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn;
    }

    /**
     * @notice Receive an exact amount of output tokens for as few input tokens as possible.
     * msg.sender should have already given the router an allowance of
     * at least amountInMax on the input token.
     *
     * @param inToken Input token.
     * @param outToken Output token.
     * @param amountOut The amount of output tokens to receive.
     * @param amountInMax The maximum amount of input tokens that can be required before the transaction reverts.
     * @param to Recipient of the output tokens.
     */
    function swapTokensForExactTokens(
        IERC20 inToken,
        IERC20 outToken,
        uint256 amountOut,
        uint256 amountInMax,
        address to
    ) external {
        require(amountOut <= amountInMax, "ARM: Excess input amount");
        _swap(inToken, outToken, amountOut, to);
    }

    /**
     * @notice Uniswap V2 Router compatible interface. Receive an exact amount of
     * output tokens for as few input tokens as possible.
     * msg.sender should have already given the router an allowance of
     * at least amountInMax on the input token.
     *
     * @param amountOut The amount of output tokens to receive.
     * @param amountInMax The maximum amount of input tokens that can be required before the transaction reverts.
     * @param path The input and output token addresses.
     * @param to Recipient of the output tokens.
     * @param deadline Unix timestamp after which the transaction will revert.
     * @return amounts The input and output token amounts.
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(amountOut <= amountInMax, "ARM: Excess input amount");
        require(path.length == 2, "ARM: Invalid path length");
        _inDeadline(deadline);

        IERC20 inToken = IERC20(path[0]);
        IERC20 outToken = IERC20(path[1]);

        _swap(inToken, outToken, amountOut, to);

        // Swaps are 1:1 so the input amount is the output amount
        amounts = new uint256[](2);
        amounts[0] = amountOut;
        amounts[1] = amountOut;
    }

    function _swap(IERC20 inToken, IERC20 outToken, uint256 amount, address to) internal {
        require(inToken == token0 && outToken == token1, "ARM: Invalid swap");

        // Transfer the input tokens from the caller to this ARM contract
        inToken.transferFrom(msg.sender, address(this), amount);

        // Transfer the same amount of output tokens to the recipient
        outToken.transfer(to, amount);
    }

    function _inDeadline(uint256 deadline) internal view {
        require(deadline >= block.timestamp, "ARM: Deadline expired");
    }

    /**
     * @notice Owner can transfer out any ERC20 token.
     */
    function transferToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }
}
