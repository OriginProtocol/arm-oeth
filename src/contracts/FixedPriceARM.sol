// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AbstractARM} from "./AbstractARM.sol";
import {IERC20} from "./Interfaces.sol";

/**
 * @title Abstract support to an ARM with a single buy and sell price.
 * @author Origin Protocol Inc
 */
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

    /// @notice Maximum amount the Operator can set the price from 1 scaled to 36 decimals.
    /// 1e33 is a 0.1% deviation, or 10 basis points.
    uint256 public constant MAX_PRICE_DEVIATION = 1e33;
    /// @notice Scale of the prices.
    uint256 public constant PRICE_SCALE = 1e36;

    uint256[48] private _gap;

    event TraderateChanged(uint256 traderate0, uint256 traderate1);

    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, address to)
        internal
        override
        returns (uint256 amountOut)
    {
        uint256 price;
        if (inToken == token0) {
            require(outToken == token1, "ARM: Invalid out token");
            price = traderate0;
        } else if (inToken == token1) {
            require(outToken == token0, "ARM: Invalid out token");
            price = traderate1;
        } else {
            revert("ARM: Invalid in token");
        }
        amountOut = amountIn * price / PRICE_SCALE;

        // Transfer the input tokens from the caller to this ARM contract
        _transferAssetFrom(address(inToken), msg.sender, address(this), amountIn);

        // Transfer the output tokens to the recipient
        _transferAsset(address(outToken), to, amountOut);
    }

    function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 amountOut, address to)
        internal
        override
        returns (uint256 amountIn)
    {
        uint256 price;
        if (inToken == token0) {
            require(outToken == token1, "ARM: Invalid out token");
            price = traderate0;
        } else if (inToken == token1) {
            require(outToken == token0, "ARM: Invalid out token");
            price = traderate1;
        } else {
            revert("ARM: Invalid in token");
        }
        amountIn = ((amountOut * PRICE_SCALE) / price) + 1; // +1 to always round in our favor

        // Transfer the input tokens from the caller to this ARM contract
        _transferAssetFrom(address(inToken), msg.sender, address(this), amountIn);

        // Transfer the output tokens to the recipient
        _transferAsset(address(outToken), to, amountOut);
    }

    /**
     * @notice Set exchange rates from an operator account from the ARM's perspective.
     * If token 0 is WETH and token 1 is stETH, then both prices will be set using the stETH/WETH price.
     * @param buyT1 The price the ARM buys Token 1 from the Trader, denominated in Token 0, scaled to 36 decimals.
     * From the Trader's perspective, this is the sell price.
     * @param sellT1 The price the ARM sells Token 1 to the Trader, denominated in Token 0, scaled to 36 decimals.
     * From the Trader's perspective, this is the buy price.
     */
    function setPrices(uint256 buyT1, uint256 sellT1) external onlyOperatorOrOwner {
        // Limit funds and loss when called by the Operator
        if (msg.sender == operator) {
            require(sellT1 >= PRICE_SCALE - MAX_PRICE_DEVIATION, "ARM: sell price too low");
            require(buyT1 <= PRICE_SCALE + MAX_PRICE_DEVIATION, "ARM: buy price too high");
        }
        uint256 _traderate0 = 1e72 / sellT1; // base (t0) -> token (t1)
        uint256 _traderate1 = buyT1; // token (t1) -> base (t0)
        _setTraderates(_traderate0, _traderate1);
    }

    function _setTraderates(uint256 _traderate0, uint256 _traderate1) internal {
        require((1e72 / (_traderate0)) > _traderate1, "ARM: Price cross");
        traderate0 = _traderate0;
        traderate1 = _traderate1;

        emit TraderateChanged(_traderate0, _traderate1);
    }
}
