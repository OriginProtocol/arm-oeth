// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC20} from "../Interfaces.sol";
import {AbstractLidoAssetAdapter} from "./AbstractLidoAssetAdapter.sol";

contract StETHAssetAdapter is AbstractLidoAssetAdapter {
    constructor(address _arm, address _weth, address _steth, address _lidoWithdrawalQueue)
        AbstractLidoAssetAdapter(_arm, _weth, _steth, _lidoWithdrawalQueue)
    {}

    function convertToAssets(uint256 shares) external pure returns (uint256 assets) {
        return shares;
    }

    function convertToShares(uint256 assets) external pure returns (uint256 shares) {
        return assets;
    }

    function _pullSharesAndConvertToSteth(address owner, uint256 shares) internal override returns (uint256 assetsOut) {
        IERC20(address(steth)).transferFrom(owner, address(this), shares);
        assetsOut = shares;
    }

    function _assetsToShares(uint256 assets) internal pure override returns (uint256 sharesOut) {
        sharesOut = assets;
    }
}
