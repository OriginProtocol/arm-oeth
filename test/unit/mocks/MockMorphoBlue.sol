// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IIrm} from "contracts/morpho/IIrm.sol";
import {IMorpho, Id, Market, MarketParams, Position} from "contracts/morpho/IMorpho.sol";
import {MarketParamsLib} from "contracts/morpho/libraries/MarketParamsLib.sol";
import {MathLib} from "contracts/morpho/libraries/MathLib.sol";
import {SharesMathLib} from "contracts/morpho/libraries/SharesMathLib.sol";

contract MockMorphoBlue is IMorpho {
    using MarketParamsLib for MarketParams;
    using MathLib for uint256;
    using SharesMathLib for uint256;

    mapping(bytes32 => Market) internal _markets;
    mapping(bytes32 => mapping(address => Position)) internal _positions;

    function createMarket(MarketParams memory marketParams) external {
        Id id = marketParams.id();
        Market storage marketState = _markets[Id.unwrap(id)];
        marketState.lastUpdate = uint128(block.timestamp);
    }

    function supply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes memory
    ) external returns (uint256 assetsSupplied, uint256 sharesSupplied) {
        require((assets == 0) != (shares == 0), "MockMorpho: invalid input");

        _accrue(marketParams);

        Id id = marketParams.id();
        Market storage marketState = _markets[Id.unwrap(id)];
        Position storage positionState = _positions[Id.unwrap(id)][onBehalf];

        if (shares == 0) {
            assetsSupplied = assets;
            sharesSupplied = assets.toSharesDown(marketState.totalSupplyAssets, marketState.totalSupplyShares);
        } else {
            sharesSupplied = shares;
            assetsSupplied = shares.toAssetsUp(marketState.totalSupplyAssets, marketState.totalSupplyShares);
        }

        IERC20(marketParams.loanToken).transferFrom(msg.sender, address(this), assetsSupplied);

        marketState.totalSupplyAssets += _toUint128(assetsSupplied);
        marketState.totalSupplyShares += _toUint128(sharesSupplied);
        positionState.supplyShares += sharesSupplied;
    }

    function withdraw(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn) {
        require((assets == 0) != (shares == 0), "MockMorpho: invalid input");

        _accrue(marketParams);

        Id id = marketParams.id();
        Market storage marketState = _markets[Id.unwrap(id)];
        Position storage positionState = _positions[Id.unwrap(id)][onBehalf];

        if (shares == 0) {
            assetsWithdrawn = assets;
            sharesWithdrawn = assets.toSharesUp(marketState.totalSupplyAssets, marketState.totalSupplyShares);
        } else {
            sharesWithdrawn = shares;
            assetsWithdrawn = shares.toAssetsDown(marketState.totalSupplyAssets, marketState.totalSupplyShares);
        }

        require(positionState.supplyShares >= sharesWithdrawn, "MockMorpho: insufficient shares");

        uint256 availableLiquidity =
            marketState.totalSupplyAssets > marketState.totalBorrowAssets
                ? marketState.totalSupplyAssets - marketState.totalBorrowAssets
                : 0;
        require(assetsWithdrawn <= availableLiquidity, "MockMorpho: insufficient liquidity");

        positionState.supplyShares -= sharesWithdrawn;
        marketState.totalSupplyAssets -= _toUint128(assetsWithdrawn);
        marketState.totalSupplyShares -= _toUint128(sharesWithdrawn);

        IERC20(marketParams.loanToken).transfer(receiver, assetsWithdrawn);
    }

    function accrueInterest(MarketParams memory marketParams) external {
        _accrue(marketParams);
    }

    function position(Id id, address user) external view returns (Position memory p) {
        return _positions[Id.unwrap(id)][user];
    }

    function market(Id id) external view returns (Market memory m) {
        return _markets[Id.unwrap(id)];
    }

    function setTotalBorrowAssets(MarketParams memory marketParams, uint128 totalBorrowAssets) external {
        _markets[Id.unwrap(marketParams.id())].totalBorrowAssets = totalBorrowAssets;
    }

    function setFee(MarketParams memory marketParams, uint128 fee) external {
        _markets[Id.unwrap(marketParams.id())].fee = fee;
    }

    function setLastUpdate(MarketParams memory marketParams, uint128 lastUpdate) external {
        _markets[Id.unwrap(marketParams.id())].lastUpdate = lastUpdate;
    }

    function _accrue(MarketParams memory marketParams) internal {
        Id id = marketParams.id();
        Market storage marketState = _markets[Id.unwrap(id)];

        if (marketState.lastUpdate == 0) {
            marketState.lastUpdate = uint128(block.timestamp);
            return;
        }

        uint256 elapsed = block.timestamp - marketState.lastUpdate;
        if (elapsed != 0 && marketState.totalBorrowAssets != 0 && marketParams.irm != address(0)) {
            uint256 borrowRate = IIrm(marketParams.irm).borrowRateView(marketParams, marketState);
            uint256 interest = uint256(marketState.totalBorrowAssets).wMulDown(borrowRate.wTaylorCompounded(elapsed));

            marketState.totalBorrowAssets += _toUint128(interest);
            marketState.totalSupplyAssets += _toUint128(interest);

            if (marketState.fee != 0) {
                uint256 feeAmount = interest.wMulDown(marketState.fee);
                uint256 feeShares =
                    feeAmount.toSharesDown(marketState.totalSupplyAssets - feeAmount, marketState.totalSupplyShares);
                marketState.totalSupplyShares += _toUint128(feeShares);
            }
        }

        marketState.lastUpdate = uint128(block.timestamp);
    }

    function _toUint128(uint256 x) internal pure returns (uint128) {
        require(x <= type(uint128).max, "MockMorpho: uint128 overflow");
        return uint128(x);
    }
}
