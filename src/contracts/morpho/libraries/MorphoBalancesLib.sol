// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IIrm} from "../IIrm.sol";
import {Id, IMorpho, Market, MarketParams, Position} from "../IMorpho.sol";
import {MarketParamsLib} from "./MarketParamsLib.sol";
import {MathLib} from "./MathLib.sol";
import {SharesMathLib} from "./SharesMathLib.sol";

library MorphoBalancesLib {
    using MarketParamsLib for MarketParams;
    using MathLib for uint256;
    using SharesMathLib for uint256;

    function expectedMarketBalances(IMorpho morpho, MarketParams memory marketParams)
        internal
        view
        returns (uint256 totalSupplyAssets, uint256 totalSupplyShares, uint256 totalBorrowAssets, uint256 totalBorrowShares)
    {
        Id id = marketParams.id();
        Market memory market = morpho.market(id);

        uint256 elapsed = block.timestamp - market.lastUpdate;
        if (elapsed != 0 && market.totalBorrowAssets != 0 && marketParams.irm != address(0)) {
            uint256 borrowRate = IIrm(marketParams.irm).borrowRateView(marketParams, market);
            uint256 interest = uint256(market.totalBorrowAssets).wMulDown(borrowRate.wTaylorCompounded(elapsed));

            market.totalBorrowAssets += _toUint128(interest);
            market.totalSupplyAssets += _toUint128(interest);

            if (market.fee != 0) {
                uint256 feeAmount = interest.wMulDown(market.fee);
                uint256 feeShares =
                    feeAmount.toSharesDown(market.totalSupplyAssets - feeAmount, market.totalSupplyShares);
                market.totalSupplyShares += _toUint128(feeShares);
            }
        }

        return (market.totalSupplyAssets, market.totalSupplyShares, market.totalBorrowAssets, market.totalBorrowShares);
    }

    function expectedSupplyAssets(IMorpho morpho, MarketParams memory marketParams, address user)
        internal
        view
        returns (uint256)
    {
        Id id = marketParams.id();
        Position memory position = morpho.position(id, user);
        (uint256 totalSupplyAssets, uint256 totalSupplyShares,,) = expectedMarketBalances(morpho, marketParams);

        return position.supplyShares.toAssetsDown(totalSupplyAssets, totalSupplyShares);
    }

    function expectedWithdrawableAssets(IMorpho morpho, MarketParams memory marketParams, address user)
        internal
        view
        returns (uint256)
    {
        uint256 userAssets = expectedSupplyAssets(morpho, marketParams, user);
        (, , uint256 totalBorrowAssets,) = expectedMarketBalances(morpho, marketParams);
        uint256 totalSupplyAssets = expectedTotalSupplyAssets(morpho, marketParams);
        uint256 availableLiquidity = totalSupplyAssets > totalBorrowAssets ? totalSupplyAssets - totalBorrowAssets : 0;

        return userAssets < availableLiquidity ? userAssets : availableLiquidity;
    }

    function expectedTotalSupplyAssets(IMorpho morpho, MarketParams memory marketParams)
        internal
        view
        returns (uint256 totalSupplyAssets)
    {
        (totalSupplyAssets,,,) = expectedMarketBalances(morpho, marketParams);
    }

    function _toUint128(uint256 x) private pure returns (uint128) {
        require(x <= type(uint128).max, "Morpho: uint128 overflow");
        return uint128(x);
    }
}
