// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC20, IWstETH} from "../Interfaces.sol";
import {AbstractLidoAssetAdapter} from "./AbstractLidoAssetAdapter.sol";

/**
 * @title Lido wstETH asset adapter
 * @notice Lido adapter for redeeming wstETH through the Lido withdrawal queue into WETH.
 * @dev wstETH is first unwrapped into stETH before opening Lido withdrawal requests.
 * @author Origin Protocol Inc
 */
contract WstETHAssetAdapter is AbstractLidoAssetAdapter {
    /// @notice wstETH token supplied by the ARM.
    IWstETH public immutable wsteth;

    /// @param _arm ARM contract authorized to use the adapter.
    /// @param _weth WETH token received after claims.
    /// @param _steth stETH token submitted to the withdrawal queue.
    /// @param _wsteth wstETH token to redeem.
    /// @param _lidoWithdrawalQueue Lido withdrawal queue contract.
    constructor(address _arm, address _weth, address _steth, address _wsteth, address _lidoWithdrawalQueue)
        AbstractLidoAssetAdapter(_arm, _weth, _steth, _lidoWithdrawalQueue)
    {
        wsteth = IWstETH(_wsteth);
    }

    /// @notice Converts wstETH shares into expected WETH assets.
    /// @param shares Amount of wstETH shares.
    /// @return assets Expected WETH assets.
    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        return wsteth.getStETHByWstETH(shares);
    }

    /// @notice Converts WETH assets into expected wstETH shares.
    /// @param assets Amount of WETH assets.
    /// @return shares Expected wstETH shares.
    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        return wsteth.getWstETHByStETH(assets);
    }

    /// @notice Pulls wstETH from `owner` and unwraps it to stETH.
    /// @param owner Address to pull wstETH from.
    /// @param shares Amount of wstETH to pull.
    /// @return assetsOut stETH amount available for Lido withdrawal requests.
    function _pullSharesAndConvertToSteth(address owner, uint256 shares) internal override returns (uint256 assetsOut) {
        IERC20(address(wsteth)).transferFrom(owner, address(this), shares);
        assetsOut = wsteth.unwrap(shares);
    }

    /// @notice Converts stETH assets back to wstETH shares.
    /// @param assets stETH amount.
    /// @return sharesOut wstETH share amount.
    function _assetsToShares(uint256 assets) internal view override returns (uint256 sharesOut) {
        sharesOut = wsteth.getWstETHByStETH(assets);
    }
}
