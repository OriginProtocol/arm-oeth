// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC20, IERC20Metadata, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMorpho, Id, MarketParams} from "../morpho/IMorpho.sol";
import {MarketParamsLib} from "../morpho/libraries/MarketParamsLib.sol";
import {MorphoBalancesLib} from "../morpho/libraries/MorphoBalancesLib.sol";
import {SharesMathLib} from "../morpho/libraries/SharesMathLib.sol";

/**
 * @title Morpho Blue Supply Vault
 * @author Origin Protocol Inc
 * @notice Single-market, non-levered Morpho Blue supply wrapper for ARM integrations.
 * @dev This wrapper intentionally exposes only the ERC-4626-like surface needed by the ARM.
 * View conversions use Morpho's interest-aware balance helpers so not-yet-accrued interest is
 * reflected in share and asset conversions. Wrapper ERC20 shares track the Morpho supply position
 * held by this contract.
 */
contract MorphoBlueSupplyVault is ERC20 {
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;
    using SafeERC20 for IERC20;
    using SharesMathLib for uint256;

    IERC20 private immutable _assetToken;

    /// @notice The Morpho Blue singleton the wrapper supplies assets into.
    IMorpho public immutable morpho;
    /// @notice The fixed Morpho market this wrapper is bound to.
    MarketParams public marketParams;
    /// @notice The deterministic Morpho market id derived from `marketParams`.
    Id public immutable marketId;

    /// @notice Emitted when assets are supplied to Morpho and wrapper shares are minted.
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    /// @notice Emitted when assets are withdrawn from Morpho and wrapper shares are burnt.
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /**
     * @notice Construct a wrapper for a single Morpho market.
     * @dev The wrapper name and symbol are derived from the market's loan token symbol. The constructor
     * grants the Morpho singleton an infinite approval for the loan token so deposits can be forwarded.
     * @param morpho_ The address of the Morpho Blue singleton.
     * @param marketParams_ The Morpho market parameters for the wrapped supply market.
     */
    constructor(address morpho_, MarketParams memory marketParams_)
        ERC20(_deriveName(marketParams_.loanToken), _deriveSymbol(marketParams_.loanToken))
    {
        require(morpho_ != address(0), "Morpho: invalid address");
        require(marketParams_.loanToken != address(0), "Morpho: invalid asset");

        morpho = IMorpho(morpho_);
        marketParams = marketParams_;
        marketId = marketParams_.id();
        _assetToken = IERC20(marketParams_.loanToken);

        _assetToken.forceApprove(morpho_, type(uint256).max);
    }

    /// @notice Return the decimals used by the underlying loan token.
    function decimals() public view override returns (uint8) {
        return IERC20Metadata(marketParams.loanToken).decimals();
    }

    /// @notice Return the loan token deposited into the wrapped Morpho market.
    function asset() public view returns (address) {
        return address(_assetToken);
    }

    /**
     * @notice Convert loan-token assets into wrapper shares using interest-aware Morpho balances.
     * @dev Uses `MorphoBalancesLib.expectedMarketBalances` so conversions include not-yet-accrued interest.
     * @param assets The amount of loan-token assets to convert.
     * @return The amount of wrapper shares quoted for `assets`.
     */
    function convertToShares(uint256 assets) public view returns (uint256) {
        (uint256 totalSupplyAssets, uint256 totalSupplyShares,,) = morpho.expectedMarketBalances(marketParams);

        return assets.toSharesDown(totalSupplyAssets, totalSupplyShares);
    }

    /**
     * @notice Convert wrapper shares into loan-token assets using interest-aware Morpho balances.
     * @dev Uses `MorphoBalancesLib.expectedMarketBalances` so conversions include not-yet-accrued interest.
     * @param shares The amount of wrapper shares to convert.
     * @return The amount of loan-token assets quoted for `shares`.
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        (uint256 totalSupplyAssets, uint256 totalSupplyShares,,) = morpho.expectedMarketBalances(marketParams);

        return shares.toAssetsDown(totalSupplyAssets, totalSupplyShares);
    }

    /**
     * @notice Return the maximum assets `owner` can withdraw.
     * @dev This is capped by both the owner's wrapper share balance and current Morpho market liquidity.
     * @param owner The account whose withdrawable assets are being queried.
     * @return The maximum loan-token assets `owner` can withdraw.
     */
    function maxWithdraw(address owner) public view returns (uint256) {
        uint256 wrapperWithdrawableAssets = morpho.expectedWithdrawableAssets(marketParams, address(this));
        uint256 ownerAssets = convertToAssets(balanceOf(owner));

        return wrapperWithdrawableAssets < ownerAssets ? wrapperWithdrawableAssets : ownerAssets;
    }

    /**
     * @notice Return the maximum shares `owner` can redeem.
     * @dev This is capped by both the owner's wrapper share balance and current Morpho market liquidity.
     * @param owner The account whose redeemable shares are being queried.
     * @return The maximum wrapper shares `owner` can redeem.
     */
    function maxRedeem(address owner) public view returns (uint256) {
        (uint256 totalSupplyAssets, uint256 totalSupplyShares, uint256 totalBorrowAssets,) =
            morpho.expectedMarketBalances(marketParams);
        uint256 availableLiquidity = totalSupplyAssets > totalBorrowAssets ? totalSupplyAssets - totalBorrowAssets : 0;
        uint256 redeemableShares = availableLiquidity.toSharesDown(totalSupplyAssets, totalSupplyShares);
        uint256 ownerShares = balanceOf(owner);

        return redeemableShares < ownerShares ? redeemableShares : ownerShares;
    }

    /**
     * @notice Preview the loan-token assets returned for redeeming wrapper shares.
     * @dev Uses `MorphoBalancesLib.expectedMarketBalances` through `convertToAssets`, so previews include
     * not-yet-accrued interest.
     * @param shares The amount of wrapper shares to redeem.
     * @return The amount of loan-token assets expected for `shares`.
     */
    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    /**
     * @notice Supply loan-token assets to Morpho and mint wrapper shares to `receiver`.
     * @dev Assets are supplied to Morpho on behalf of this wrapper, and the resulting Morpho supply shares
     * are mirrored as wrapper ERC20 shares for `receiver`.
     * @param assets The amount of loan-token assets to supply.
     * @param receiver The account receiving the minted wrapper shares.
     * @return shares The amount of wrapper shares minted.
     */
    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        _assetToken.safeTransferFrom(msg.sender, address(this), assets);

        (uint256 assetsSupplied, uint256 sharesSupplied) = morpho.supply(marketParams, assets, 0, address(this), "");
        require(assetsSupplied == assets, "Morpho: partial supply");

        _mint(receiver, sharesSupplied);

        emit Deposit(msg.sender, receiver, assetsSupplied, sharesSupplied);

        return sharesSupplied;
    }

    /**
     * @notice Withdraw an exact amount of loan-token assets from Morpho to `receiver`.
     * @dev Burns the exact wrapper shares removed from the wrapper's Morpho supply position. The call is
     * limited by both the owner's balance and current Morpho market liquidity.
     * @param assets The amount of loan-token assets to withdraw.
     * @param receiver The account receiving the withdrawn assets.
     * @param owner The account whose wrapper shares are burnt.
     * @return shares The amount of wrapper shares burnt.
     */
    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256 shares) {
        require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");

        (uint256 assetsWithdrawn, uint256 sharesWithdrawn) =
            morpho.withdraw(marketParams, assets, 0, address(this), receiver);
        require(assetsWithdrawn == assets, "Morpho: partial withdraw");

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, sharesWithdrawn);
        }
        _burn(owner, sharesWithdrawn);

        emit Withdraw(msg.sender, receiver, owner, assetsWithdrawn, sharesWithdrawn);

        return sharesWithdrawn;
    }

    /**
     * @notice Redeem wrapper shares for loan-token assets withdrawn from Morpho to `receiver`.
     * @dev Burns `shares` from `owner` and withdraws against the wrapper's Morpho supply position. The call
     * is limited by both the owner's balance and current Morpho market liquidity.
     * @param shares The amount of wrapper shares to redeem.
     * @param receiver The account receiving the withdrawn assets.
     * @param owner The account whose wrapper shares are burnt.
     * @return assets The amount of loan-token assets withdrawn.
     */
    function redeem(uint256 shares, address receiver, address owner) public returns (uint256 assets) {
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        (uint256 assetsWithdrawn, uint256 sharesWithdrawn) =
            morpho.withdraw(marketParams, 0, shares, address(this), receiver);
        require(sharesWithdrawn == shares, "Morpho: unexpected shares");

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, sharesWithdrawn);
        }
        _burn(owner, sharesWithdrawn);

        emit Withdraw(msg.sender, receiver, owner, assetsWithdrawn, sharesWithdrawn);

        return assetsWithdrawn;
    }

    /// @notice Derive the wrapper name from the market loan token symbol.
    function _deriveName(address loanToken) private view returns (string memory) {
        return string.concat("Morpho Blue ", IERC20Metadata(loanToken).symbol(), " Supply");
    }

    /// @notice Derive the wrapper symbol from the market loan token symbol.
    function _deriveSymbol(address loanToken) private view returns (string memory) {
        return string.concat("mb", IERC20Metadata(loanToken).symbol());
    }
}
