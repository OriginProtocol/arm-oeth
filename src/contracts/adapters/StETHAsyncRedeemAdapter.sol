// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC20} from "../Interfaces.sol";
import {AbstractLidoAsyncRedeemAdapter} from "./AbstractLidoAsyncRedeemAdapter.sol";

contract StETHAsyncRedeemAdapter is AbstractLidoAsyncRedeemAdapter {
    constructor(address _arm, address _weth, address _steth, address _lidoWithdrawalQueue)
        AbstractLidoAsyncRedeemAdapter(_arm, _weth, _steth, _lidoWithdrawalQueue)
    {}

    function convertToAssets(uint256 shares) public pure override returns (uint256 assetsOut) {
        assetsOut = shares;
    }

    function convertToShares(uint256 assetsIn) public pure override returns (uint256 sharesOut) {
        sharesOut = assetsIn;
    }

    function _pullSharesAndConvertToSteth(address owner, uint256 shares) internal override returns (uint256 assetsOut) {
        IERC20(address(steth)).transferFrom(owner, address(this), shares);
        assetsOut = shares;
    }

    function _stethToShares(uint256 stethAmount) internal pure override returns (uint256 sharesOut) {
        sharesOut = stethAmount;
    }
}
