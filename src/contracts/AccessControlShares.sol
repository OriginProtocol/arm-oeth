// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {MultiLP} from "./MultiLP.sol";

abstract contract AccessControlShares is MultiLP {
    uint256 public totalSupplyCap;
    mapping(address lp => uint256 shares) public liquidityProviderCaps;

    uint256[50] private _gap;

    event LiquidityProviderCap(address indexed liquidityProvider, uint256 cap);
    event TotalSupplyCap(uint256 shares);

    function _postDepositHook(uint256) internal virtual override {
        require(liquidityProviderCaps[msg.sender] >= balanceOf(msg.sender), "ARM: LP cap exceeded");
        // total supply has already been updated
        require(totalSupplyCap >= totalSupply(), "ARM: Supply cap exceeded");
    }

    function _postWithdrawHook(uint256) internal virtual override {
        // Do nothing
    }

    function setLiquidityProviderCap(address liquidityProvider, uint256 cap) external onlyOwner {
        liquidityProviderCaps[liquidityProvider] = cap;

        emit LiquidityProviderCap(liquidityProvider, cap);
    }

    function setTotalSupplyCap(uint256 _totalSupplyCap) external onlyOwner {
        totalSupplyCap = _totalSupplyCap;

        emit TotalSupplyCap(_totalSupplyCap);
    }
}
