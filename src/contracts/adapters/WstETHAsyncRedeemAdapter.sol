// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC20, IWstETH} from "../Interfaces.sol";
import {AbstractLidoAsyncRedeemAdapter} from "./AbstractLidoAsyncRedeemAdapter.sol";

contract WstETHAsyncRedeemAdapter is AbstractLidoAsyncRedeemAdapter {
    IWstETH public immutable wsteth;

    constructor(address _arm, address _weth, address _steth, address _wsteth, address _lidoWithdrawalQueue)
        AbstractLidoAsyncRedeemAdapter(_arm, _weth, _steth, _lidoWithdrawalQueue)
    {
        wsteth = IWstETH(_wsteth);
    }

    function convertToAssets(uint256 shares) public view override returns (uint256 assetsOut) {
        assetsOut = wsteth.getStETHByWstETH(shares);
    }

    function convertToShares(uint256 assetsIn) public view override returns (uint256 sharesOut) {
        sharesOut = wsteth.getWstETHByStETH(assetsIn);
    }

    function _pullSharesAndConvertToSteth(address owner, uint256 shares) internal override returns (uint256 assetsOut) {
        IERC20(address(wsteth)).transferFrom(owner, address(this), shares);
        assetsOut = wsteth.unwrap(shares);
    }

    function _stethToShares(uint256 stethAmount) internal view override returns (uint256 sharesOut) {
        sharesOut = wsteth.getWstETHByStETH(stethAmount);
    }
}
