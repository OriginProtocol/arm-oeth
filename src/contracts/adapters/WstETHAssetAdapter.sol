// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC20, IWstETH} from "../Interfaces.sol";
import {AbstractLidoAssetAdapter} from "./AbstractLidoAssetAdapter.sol";

contract WstETHAssetAdapter is AbstractLidoAssetAdapter {
    IWstETH public immutable wsteth;

    constructor(address _arm, address _weth, address _steth, address _wsteth, address _lidoWithdrawalQueue)
        AbstractLidoAssetAdapter(_arm, _weth, _steth, _lidoWithdrawalQueue)
    {
        wsteth = IWstETH(_wsteth);
    }

    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        return wsteth.getStETHByWstETH(shares);
    }

    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        return wsteth.getWstETHByStETH(assets);
    }

    function _pullSharesAndConvertToSteth(address owner, uint256 shares) internal override returns (uint256 assetsOut) {
        IERC20(address(wsteth)).transferFrom(owner, address(this), shares);
        assetsOut = wsteth.unwrap(shares);
    }

    function _assetsToShares(uint256 assets) internal view override returns (uint256 sharesOut) {
        sharesOut = wsteth.getWstETHByStETH(assets);
    }
}
