// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.36;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {BaseAssetConfig} from "../AbstractARM.sol";
import {IAssetAdapter, IERC20} from "../Interfaces.sol";

/// @title ARM adapter operations
/// @notice Linked library for protocol adapter redemption and mint lifecycle operations.
/// @dev External calls execute by delegatecall and mutate only the explicitly passed ARM storage references.
/// @author Origin Protocol Inc
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

    /// @notice Register a base asset and its adapter, prices, and available swap liquidity.
    /// @dev Approves the adapter to transfer the base asset and appends the asset to `baseAssets`.
    /// @param baseAssets ARM storage array of registered base-asset addresses.
    /// @param configs ARM storage mapping from base assets to their configuration.
    /// @param liquidityAsset Asset used for LP deposits and base-asset quote pricing.
    /// @param newBaseAsset Base asset to register. Its token decimals must be either 6 or 18.
    /// @param adapter Adapter that converts and handles protocol minting or redemption for the base asset.
    /// @param buyPrice Price paid by the ARM when buying the base asset, scaled to 36 decimals.
    /// For example, 0.998e36 is 0.998 liquidity asset per base asset.
    /// @param sellPrice Price charged by the ARM when selling the base asset, scaled to 36 decimals.
    /// For example, 1.001e36 is 1.001 liquidity asset per base asset.
    /// @param buyAmount Liquidity asset available at `buyPrice`, in native liquidity-asset decimals.
    /// For example, 100e6 is 100 USDC when the liquidity asset has 6 decimals.
    /// @param sellAmount Base asset available at `sellPrice`, in native base-asset decimals.
    /// For example, 100e18 is 100 base assets when the base asset has 18 decimals.
    /// @param newCrossPrice Valuation price used by totalAssets(), scaled to 36 decimals.
    /// For example, 1e36 values one base asset at one liquidity asset.
    /// @param peggedToLiquidityAsset Whether conversions bypass the adapter and use decimal-scaled 1:1 amounts.
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

    /// @notice Request protocol redemption of base-asset shares through their configured adapter.
    /// @dev Adds the liquidity-denominated amount expected from the adapter to `pendingRedeemAssets`.
    /// @param configs ARM storage mapping from base assets to their configuration.
    /// @param redeemBaseAsset Base asset whose shares are submitted for redemption.
    /// @param shares Base-asset shares to redeem, in native base-asset decimals.
    /// For example, 100e18 is 100 shares when the base asset has 18 decimals.
    /// @return sharesRequested Base-asset shares accepted by the adapter.
    /// @return assetsExpected Liquidity assets expected from settlement, in native liquidity-asset decimals.
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

    /// @notice Claim completed base-asset redemptions through their configured adapter.
    /// @dev Removes the adapter's expected liquidity amount from `pendingRedeemAssets`; any settlement shortfall
    ///      is reflected in totalAssets() after the expected amount is removed.
    /// @param configs ARM storage mapping from base assets to their configuration.
    /// @param redeemBaseAsset Base asset whose completed redemptions are claimed.
    /// @param shares Base-asset shares to claim, in native base-asset decimals.
    /// For example, 100e18 is 100 shares when the base asset has 18 decimals.
    /// @return sharesClaimed Base-asset shares removed from the adapter's redemption queue.
    /// @return assetsExpected Liquidity assets expected for the claimed shares.
    /// @return assetsReceived Liquidity assets actually transferred to the ARM.
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

    /// @notice Commit liquidity assets to an asynchronous base-asset mint through an adapter.
    /// @dev Withdraws a shortfall from `activeMarket` when necessary, preserves liquidity reserved for LP
    ///      withdrawals, and tracks expected base shares in `pendingMintShares` for totalAssets() valuation.
    /// @param configs ARM storage mapping from base assets to their configuration.
    /// @param pendingMintShares ARM storage mapping of base-asset shares expected from outstanding mints.
    /// @param liquidityAsset Asset committed to the mint.
    /// @param activeMarket ERC-4626 market used to source a liquidity shortfall, or address(0) when none is active.
    /// @param reservedWithdrawLiquidity Liquidity reserved for outstanding LP withdrawals, in native decimals.
    /// For example, 100e6 reserves 100 USDC when the liquidity asset has 6 decimals.
    /// @param mintBaseAsset Base asset expected from mint settlement.
    /// @param assets Liquidity assets offered to the adapter, in native liquidity-asset decimals.
    /// For example, 100e6 offers 100 USDC when the liquidity asset has 6 decimals.
    /// @return assetsRequested Liquidity assets accepted by the adapter.
    /// @return sharesExpected Base-asset shares expected from settlement.
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

    /// @notice Claim asynchronously minted base-asset shares from their configured adapter.
    /// @dev Removes the claimed shares from `pendingMintShares` after the adapter transfers settled inventory.
    /// @param configs ARM storage mapping from base assets to their configuration.
    /// @param pendingMintShares ARM storage mapping of base-asset shares expected from outstanding mints.
    /// @param mintBaseAsset Base asset being claimed from the adapter.
    /// @param shares Pending base-asset shares to claim, in native base-asset decimals.
    /// For example, 100e18 is 100 shares when the base asset has 18 decimals.
    /// @return sharesClaimed Base-asset shares removed from the adapter's mint queue.
    /// @return assetsExpected Liquidity assets committed for the claimed shares.
    /// @return sharesReceived Base-asset shares actually transferred to the ARM.
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
