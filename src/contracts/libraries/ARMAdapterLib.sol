// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.36;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {BaseAssetConfig} from "../AbstractARM.sol";
import {IAssetAdapter, IERC20} from "../Interfaces.sol";

/// @title ARM adapter operations
/// @notice Linked library for protocol adapter redemption and mint lifecycle operations.
/// @dev External calls execute by delegatecall and mutate only the explicitly passed ARM storage references.
library ARMAdapterLib {
    uint256 private constant MAX_CROSS_PRICE_DEVIATION = 20e32;
    uint256 private constant PRICE_SCALE = 1e36;

    error UnsupportedAsset(); // 0x24a01144
    error InsufficientLiquidity(); // 0xbb55fd27
    error InvalidAsset(); // 0xc891add2
    error InvalidAdapter(); // 0xfbf66df1
    error AssetAlreadySupported(); // 0xb1093e5b
    error InvalidAssetDecimals(); // 0xe2364765
    error InvalidAdapterAsset(); // 0x030f0830
    error InvalidBuyPrice(); // 0x36c64b27
    error SellPriceTooLow(); // 0x2394065c
    error CrossPriceTooLow(); // 0xea59e662
    error CrossPriceTooHigh(); // 0x682101d7

    event BaseAssetAdded(
        address indexed asset,
        address indexed adapter,
        uint256 buyPrice,
        uint256 sellPrice,
        uint256 crossPrice,
        bool peggedToLiquidityAsset
    );

    function addBaseAsset(
        address[] storage baseAssets,
        mapping(address asset => BaseAssetConfig) storage configs,
        address liquidityAsset,
        address newBaseAsset,
        address adapter,
        uint256 buyPrice,
        uint256 sellPrice,
        uint256 buyAmount,
        uint256 sellAmount,
        uint256 newCrossPrice,
        bool peggedToLiquidityAsset
    ) external {
        if (newBaseAsset == address(0)) revert InvalidAsset();
        if (adapter == address(0)) revert InvalidAdapter();
        if (configs[newBaseAsset].adapter != address(0)) revert AssetAlreadySupported();

        uint8 baseDecimals = IERC20(newBaseAsset).decimals();
        if (baseDecimals != 6 && baseDecimals != 18) revert InvalidAssetDecimals();
        if (IAssetAdapter(adapter).asset() != liquidityAsset) revert InvalidAdapterAsset();
        if (newCrossPrice < PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION) revert CrossPriceTooLow();
        if (newCrossPrice > PRICE_SCALE + MAX_CROSS_PRICE_DEVIATION) revert CrossPriceTooHigh();
        if (sellPrice < newCrossPrice) revert SellPriceTooLow();
        if (buyPrice < MAX_CROSS_PRICE_DEVIATION || buyPrice >= newCrossPrice) revert InvalidBuyPrice();

        baseAssets.push(newBaseAsset);
        IERC20(newBaseAsset).approve(adapter, type(uint256).max);
        configs[newBaseAsset] = BaseAssetConfig({
            buyPrice: SafeCast.toUint128(buyPrice),
            sellPrice: SafeCast.toUint128(sellPrice),
            buyLiquidityRemaining: SafeCast.toUint128(buyAmount),
            sellLiquidityRemaining: SafeCast.toUint128(sellAmount),
            crossPrice: SafeCast.toUint128(newCrossPrice),
            pendingRedeemAssets: 0,
            peggedToLiquidityAsset: peggedToLiquidityAsset,
            baseAssetDecimals: baseDecimals,
            adapter: adapter
        });

        emit BaseAssetAdded(newBaseAsset, adapter, buyPrice, sellPrice, newCrossPrice, peggedToLiquidityAsset);
    }

    function requestRedeem(
        mapping(address asset => BaseAssetConfig) storage configs,
        address redeemBaseAsset,
        uint256 shares
    ) external returns (uint256 sharesRequested, uint256 assetsExpected) {
        BaseAssetConfig storage config = configs[redeemBaseAsset];
        if (config.adapter == address(0)) revert UnsupportedAsset();

        (sharesRequested, assetsExpected) = IAssetAdapter(config.adapter).requestRedeem(shares);
        config.pendingRedeemAssets = SafeCast.toUint128(uint256(config.pendingRedeemAssets) + assetsExpected);
    }

    function claimRedeem(
        mapping(address asset => BaseAssetConfig) storage configs,
        address redeemBaseAsset,
        uint256 shares
    ) external returns (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived) {
        BaseAssetConfig storage config = configs[redeemBaseAsset];
        if (config.adapter == address(0)) revert UnsupportedAsset();

        (sharesClaimed, assetsExpected, assetsReceived) = IAssetAdapter(config.adapter).redeem(shares);
        config.pendingRedeemAssets = SafeCast.toUint128(uint256(config.pendingRedeemAssets) - assetsExpected);
    }

    function requestMint(
        mapping(address asset => BaseAssetConfig) storage configs,
        mapping(address asset => uint256 shares) storage pendingMintShares,
        address liquidityAsset,
        address activeMarket,
        uint128 reservedWithdrawLiquidity,
        address mintBaseAsset,
        uint256 assets
    ) external returns (uint256 assetsRequested, uint256 sharesExpected) {
        BaseAssetConfig storage config = configs[mintBaseAsset];
        address adapter = config.adapter;
        if (adapter == address(0)) revert UnsupportedAsset();

        _ensureLiquidityAvailable(assets, liquidityAsset, activeMarket, reservedWithdrawLiquidity);

        IERC20 liquidityToken = IERC20(liquidityAsset);
        if (liquidityToken.allowance(address(this), adapter) < assets) {
            liquidityToken.approve(adapter, type(uint256).max);
        }

        (assetsRequested, sharesExpected) = IAssetAdapter(adapter).requestMint(assets);
        pendingMintShares[mintBaseAsset] += sharesExpected;
    }

    function claimMint(
        mapping(address asset => BaseAssetConfig) storage configs,
        mapping(address asset => uint256 shares) storage pendingMintShares,
        address mintBaseAsset,
        uint256 shares
    ) external returns (uint256 sharesClaimed, uint256 assetsExpected, uint256 sharesReceived) {
        BaseAssetConfig storage config = configs[mintBaseAsset];
        if (config.adapter == address(0)) revert UnsupportedAsset();

        (sharesClaimed, assetsExpected, sharesReceived) = IAssetAdapter(config.adapter).claimMint(shares);
        pendingMintShares[mintBaseAsset] -= sharesClaimed;
    }

    function _ensureLiquidityAvailable(
        uint256 amount,
        address liquidityAsset,
        address activeMarket,
        uint128 reservedWithdrawLiquidity
    ) private {
        uint256 liquidityBalance = IERC20(liquidityAsset).balanceOf(address(this));
        uint256 requiredLiquidity = amount + reservedWithdrawLiquidity;
        if (requiredLiquidity <= liquidityBalance) return;

        if (activeMarket == address(0)) revert InsufficientLiquidity();

        uint256 shortfall = requiredLiquidity - liquidityBalance;
        try IERC4626(activeMarket).withdraw(shortfall, address(this), address(this)) {}
        catch {
            revert InsufficientLiquidity();
        }
    }
}
