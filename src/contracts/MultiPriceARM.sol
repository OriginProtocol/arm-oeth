// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AbstractARM} from "./AbstractARM.sol";
import {IERC20} from "./Interfaces.sol";

abstract contract MultiPriceARM is AbstractARM {
    /// @notice The token being bought by the ARM at a discount. eg stETH
    address private immutable discountToken;
    /// @notice The token being sold by the ARM. eg WETH
    address private immutable liquidityToken;

    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant DISCOUNT_MULTIPLIER = 1e13;
    /// @notice The amount of tranche allocation and remaining amounts are multiplied by to get the actual amount.
    /// min amount is 0.1 Ether, Max amount is 6,553.6 Ether
    uint256 public constant TRANCHE_AMOUNT_MULTIPLIER = 1e17;

    uint256 private constant DISCOUNT_INDEX = 0;
    uint256 private constant LIQUIDITY_ALLOCATED_INDEX = 1;
    uint256 private constant LIQUIDITY_REMAINING_INDEX = 2;

    /// @notice The five liquidity tranches of the ARM
    /// Each tranche is represented by three uint16 values:
    /// 0 - the discount from the liquidity token scaled to 1e5
    //      eg an 8 basis point discount (0.08%) would be 800 with a price of 0.9992
    /// 1 - the amount of liquidity allocated to this tranche. 1 = 0.1 Ether
    /// 2 - the amount of liquidity remaining in this tranche. 1 = 0.1 Ether
    /// The three tranche values are repeated five times in the array as follows:
    /// [discount, allocated, remaining, discount, allocated, remaining, ...]
    /// @dev Five tranches are used as they fit in a single storage slot
    uint16[15] private tranches;

    constructor(address _discountToken, address _liquidityToken) {
        discountToken = _discountToken;
        liquidityToken = _liquidityToken;
    }

    function _postDepositHook(uint256 liquidityAmount) internal virtual {
        uint256 remainingLiquidity = liquidityAmount;
        uint256 unallocatedLiquidity;
        uint256 liquidityToAdd;

        // Read the tranches from storage into memory
        uint16[15] memory tranchesMem = tranches;

        // Fill the tranches with the new liquidity from first to last
        for (uint256 i = 0; i < tranchesMem.length; i + 3) {
            unallocatedLiquidity =
                tranchesMem[i + LIQUIDITY_ALLOCATED_INDEX] - tranchesMem[i + LIQUIDITY_REMAINING_INDEX];

            liquidityToAdd = remainingLiquidity <= unallocatedLiquidity ? remainingLiquidity : unallocatedLiquidity;

            // Update the liquidity remaining in memory
            tranchesMem[i + LIQUIDITY_REMAINING_INDEX] += SafeCast.toUint16(liquidityToAdd / TRANCHE_AMOUNT_MULTIPLIER);

            remainingLiquidity -= liquidityToAdd;

            if (remainingLiquidity == 0) {
                return;
            }
        }

        // Write back the tranche data to storage once
        tranches = tranchesMem;
    }

    function _postRedeemHook(uint256 liquidityAmount) internal virtual {
        uint256 remainingLiquidity = liquidityAmount;
        uint256 liquidityToRemove;

        uint16[15] memory tranchesMem = tranches;

        // Take liquidity from the tranches from last to first
        for (uint256 i = tranchesMem.length; i > 2;) {
            i = i - 3;
            liquidityToRemove = remainingLiquidity <= tranchesMem[i + LIQUIDITY_REMAINING_INDEX]
                ? remainingLiquidity
                : tranchesMem[i + LIQUIDITY_REMAINING_INDEX];

            tranchesMem[i + LIQUIDITY_REMAINING_INDEX] -=
                SafeCast.toUint16(liquidityToRemove / TRANCHE_AMOUNT_MULTIPLIER);

            remainingLiquidity -= liquidityToRemove;

            if (remainingLiquidity == 0) {
                return;
            }
        }

        // Write back the tranche data to storage once
        tranches = tranchesMem;
    }

    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, address to)
        internal
        override
        returns (uint256 amountOut)
    {
        uint256 price;
        if (address(inToken) == discountToken) {
            require(address(outToken) == liquidityToken, "ARM: Invalid token");
            price = _calcPriceFromDiscount(amountIn);
        } else if (address(inToken) == liquidityToken) {
            require(address(outToken) == discountToken, "ARM: Invalid token");
            price = _calcPriceFromLiquidity(amountIn);
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
        if (address(inToken) == discountToken) {
            require(address(outToken) == liquidityToken, "ARM: Invalid token");
            price = _calcPriceFromLiquidity(amountOut);
        } else if (address(inToken) == liquidityToken) {
            require(address(outToken) == discountToken, "ARM: Invalid token");
            price = _calcPriceFromDiscount(amountOut);
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

    /// @dev Calculate the volume weighted price from the available liquidity amount. eg WETH amount
    function _calcPriceFromLiquidity(uint256 liquiditySwapAmount) internal returns (uint256 price) {
        uint16[15] memory tranchesMem = tranches;

        uint256 trancheVolume;
        uint256 totalPriceVolume;
        uint256 remainingSwapVolume = liquiditySwapAmount;

        // For each tranche
        for (uint256 i = 0; i < tranchesMem.length; i + 3) {
            uint256 actualLiquidityRemainingInTranche =
                tranchesMem[i + LIQUIDITY_REMAINING_INDEX] * TRANCHE_AMOUNT_MULTIPLIER;
            trancheVolume = remainingSwapVolume <= actualLiquidityRemainingInTranche
                ? remainingSwapVolume
                : actualLiquidityRemainingInTranche;

            // Update the liquidity remaining in memory
            tranchesMem[i + LIQUIDITY_REMAINING_INDEX] =
                SafeCast.toUint16((actualLiquidityRemainingInTranche - trancheVolume) / TRANCHE_AMOUNT_MULTIPLIER);

            // If there is no liquidity in the tranche then move to the next tranche
            if (trancheVolume == 0) {
                continue;
            }

            uint256 actualPrice = PRICE_PRECISION - (tranchesMem[i + DISCOUNT_INDEX] * DISCOUNT_MULTIPLIER);
            totalPriceVolume += actualPrice * trancheVolume;
            remainingSwapVolume -= trancheVolume;

            // Break from the loop if we have enough liquidity
            if (remainingSwapVolume == 0) {
                break;
            }
        }

        // If there is not enough liquidity in all the tranches then revert
        require(remainingSwapVolume == 0, "ARM: Not enough liquidity");

        // Write back the tranche data to storage once
        tranches = tranchesMem;

        // Calculate the volume weighted average price which is returned
        return totalPriceVolume / liquiditySwapAmount;
    }

    /// @dev Calculate the volume weighted price from the available discount amount. eg stETH amount
    function _calcPriceFromDiscount(uint256 discountSwapAmount) internal returns (uint256 price) {
        uint16[15] memory tranchesMem = tranches;

        uint256 discountTrancheVolume;
        uint256 totalDiscountPriceVolume;
        uint256 remainingDiscountSwapVolume = discountSwapAmount;

        // For each tranche
        for (uint256 i = 0; i < tranchesMem.length; i + 3) {
            uint256 tranchePrice = (PRICE_PRECISION - (tranchesMem[i + DISCOUNT_INDEX] * DISCOUNT_MULTIPLIER));
            // Convert the tranche liquidity to the discount token
            uint256 actualDiscountRemainingInTranche =
                tranchesMem[i + LIQUIDITY_REMAINING_INDEX] * TRANCHE_AMOUNT_MULTIPLIER * PRICE_PRECISION / tranchePrice;
            discountTrancheVolume = remainingDiscountSwapVolume <= actualDiscountRemainingInTranche
                ? remainingDiscountSwapVolume
                : actualDiscountRemainingInTranche;

            // Update the liquidity remaining in memory
            uint256 liquidityTrancheVolume = discountTrancheVolume * tranchePrice / PRICE_PRECISION;
            tranchesMem[i + LIQUIDITY_REMAINING_INDEX] = tranchesMem[i + LIQUIDITY_REMAINING_INDEX]
                - SafeCast.toUint16(liquidityTrancheVolume / TRANCHE_AMOUNT_MULTIPLIER);

            // If there is no liquidity in the tranche then move to the next tranche
            if (discountTrancheVolume == 0) {
                continue;
            }

            totalDiscountPriceVolume += discountTrancheVolume * PRICE_PRECISION * PRICE_PRECISION / tranchePrice;
            remainingDiscountSwapVolume -= discountTrancheVolume;

            // Break from the loop if we have enough liquidity
            if (remainingDiscountSwapVolume == 0) {
                break;
            }
        }

        // If there is not enough liquidity in all the tranches then revert
        require(remainingDiscountSwapVolume == 0, "ARM: Not enough liquidity");

        // Write back the tranche data to storage once
        tranches = tranchesMem;

        // Calculate the volume weighted average price
        uint256 discountPrice = totalDiscountPriceVolume / discountSwapAmount;
        // Convert back to a liquidity price.
        return PRICE_PRECISION * PRICE_PRECISION / discountPrice;
    }

    /**
     * @notice Calculate transfer amount for outToken.
     * Some tokens like stETH transfer less than the requested amount due to internal mechanics.
     */
    function _calcTransferAmount(address, uint256 amount) internal view virtual returns (uint256 transferAmount) {
        transferAmount = amount;
    }
}
