// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AbstractARM} from "./AbstractARM.sol";
import {IERC20} from "./Interfaces.sol";

abstract contract FixedPriceARM is AbstractARM {
    /**
     * @notice For one `token0` from a Trader, how many `token1` does the pool send.
     * For example, if `token0` is WETH and `token1` is stETH then
     * `traderate0` is the WETH/stETH price.
     * From a Trader's perspective, this is the stETH/WETH buy price.
     * Rate is to 36 decimals (1e36).
     */
    uint256 public traderate0;
    /**
     * @notice For one `token1` from a Trader, how many `token0` does the pool send.
     * For example, if `token0` is WETH and `token1` is stETH then
     * `traderate1` is the stETH/WETH price.
     * From a Trader's perspective, this is the stETH/WETH sell price.
     * Rate is to 36 decimals (1e36).
     */
    uint256 public traderate1;

    /// @dev Maximum operator settable traderate. 1e36
    uint256 internal constant MAX_OPERATOR_RATE = 1005 * 1e33;
    /// @dev Minimum funds to allow operator to price changes
    uint256 public minimumFunds;

    uint256[50] private _gap;

    event TraderateChanged(uint256 traderate0, uint256 traderate1);

    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, address to)
        internal
        override
        returns (uint256 amountOut)
    {
        uint256 price;
        if (inToken == token0) {
            require(outToken == token1, "ARM: Invalid token");
            price = traderate0;
        } else if (inToken == token1) {
            require(outToken == token0, "ARM: Invalid token");
            price = traderate1;
        } else {
            revert("ARM: Invalid token");
        }
        amountOut = amountIn * price / 1e36;

        // Transfer the input tokens from the caller to this ARM contract
        inToken.transferFrom(msg.sender, address(this), amountIn);

        // Transfer the output tokens to the recipient
        uint256 transferAmountOut = _calcTransferAmount(address(outToken), amountOut);
        outToken.transfer(to, transferAmountOut);
    }

    function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 amountOut, address to)
        internal
        override
        returns (uint256 amountIn)
    {
        uint256 price;
        if (inToken == token0) {
            require(outToken == token1, "ARM: Invalid token");
            price = traderate0;
        } else if (inToken == token1) {
            require(outToken == token0, "ARM: Invalid token");
            price = traderate1;
        } else {
            revert("ARM: Invalid token");
        }
        amountIn = ((amountOut * 1e36) / price) + 1; // +1 to always round in our favor

        // Transfer the input tokens from the caller to this ARM contract
        inToken.transferFrom(msg.sender, address(this), amountIn);

        // Transfer the output tokens to the recipient
        uint256 transferAmountOut = _calcTransferAmount(address(outToken), amountOut);
        outToken.transfer(to, transferAmountOut);
    }

    /**
     * @notice Calculate transfer amount for outToken.
     * Some tokens like stETH transfer less than the requested amount due to internal mechanics.
     */
    function _calcTransferAmount(address, uint256 amount) internal view virtual returns (uint256 transferAmount) {
        transferAmount = amount;
    }

    /**
     * @notice Set exchange rates from an operator account
     * @param buyT1 The buy price of Token 1 (t0 -> t1), denominated in Token 0. 1e36
     * @param sellT1 The sell price of Token 1 (t1 -> t0), denominated in Token 0. 1e36
     */
    function setPrices(uint256 buyT1, uint256 sellT1) external onlyOperatorOrOwner {
        uint256 _traderate0 = 1e72 / sellT1; // base (t0) -> token (t1)
        uint256 _traderate1 = buyT1; // token (t1) -> base (t0)
        // Limit funds and loss when called by operator
        if (msg.sender == operator) {
            uint256 currentFunds = token0.balanceOf(address(this)) + token1.balanceOf(address(this));
            require(currentFunds > minimumFunds, "ARM: Too much loss");
            require(_traderate0 <= MAX_OPERATOR_RATE, "ARM: Traderate too high");
            require(_traderate1 <= MAX_OPERATOR_RATE, "ARM: Traderate too high");
        }
        _setTraderates(_traderate0, _traderate1);
    }

    /**
     * @notice Sets the minimum funds to allow operator price changes
     */
    function setMinimumFunds(uint256 _minimumFunds) external onlyOwner {
        minimumFunds = _minimumFunds;
    }

    function _setTraderates(uint256 _traderate0, uint256 _traderate1) internal {
        require((1e72 / (_traderate0)) > _traderate1, "ARM: Price cross");
        traderate0 = _traderate0;
        traderate1 = _traderate1;

        emit TraderateChanged(_traderate0, _traderate1);
    }
}
