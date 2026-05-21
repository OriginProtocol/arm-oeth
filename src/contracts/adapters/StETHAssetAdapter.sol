// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC20} from "../Interfaces.sol";
import {AbstractLidoAssetAdapter} from "./AbstractLidoAssetAdapter.sol";

/**
 * @title Lido stETH asset adapter
 * @notice Lido adapter for redeeming stETH through the Lido withdrawal queue into WETH.
 * @author Origin Protocol Inc
 */
contract StETHAssetAdapter is AbstractLidoAssetAdapter {
    /// @param _arm ARM contract authorized to use the adapter.
    /// @param _weth WETH token received after claims.
    /// @param _steth stETH token submitted to the withdrawal queue.
    /// @param _lidoWithdrawalQueue Lido withdrawal queue contract.
    constructor(address _arm, address _weth, address _steth, address _lidoWithdrawalQueue)
        AbstractLidoAssetAdapter(_arm, _weth, _steth, _lidoWithdrawalQueue)
    {}

    /// @notice Converts stETH shares to expected WETH assets at a 1:1 rate.
    /// @param shares Amount of stETH shares.
    /// @return assets Expected WETH assets.
    function convertToAssets(uint256 shares) external pure returns (uint256 assets) {
        return shares;
    }

    /// @notice Converts WETH assets to expected stETH shares at a 1:1 rate.
    /// @param assets Amount of WETH assets.
    /// @return shares Expected stETH shares.
    function convertToShares(uint256 assets) external pure returns (uint256 shares) {
        return assets;
    }

    /// @notice Pulls stETH from `owner` for submission to Lido.
    /// @param owner Address to pull stETH from.
    /// @param shares Amount of stETH to pull.
    /// @return assetsOut stETH amount available for Lido withdrawal requests.
    function _pullSharesAndConvertToSteth(address owner, uint256 shares) internal override returns (uint256 assetsOut) {
        IERC20(address(steth)).transferFrom(owner, address(this), shares);
        assetsOut = shares;
    }

    /// @notice Converts stETH assets back to stETH shares at a 1:1 rate.
    /// @param assets stETH amount.
    /// @return sharesOut stETH share amount.
    function _assetsToShares(uint256 assets) internal pure override returns (uint256 sharesOut) {
        sharesOut = assets;
    }
}
