// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {MultiLP} from "./MultiLP.sol";

abstract contract AccessControlLP is MultiLP {
    uint256 public totalAssetsCap;
    mapping(address lp => uint256 cap) public liquidityProviderCaps;

    uint256[50] private _gap;

    event LiquidityProviderCap(address indexed liquidityProvider, uint256 cap);
    event TotalAssetsCap(uint256 cap);

    function _postDepositHook(uint256 assets) internal virtual override {
        require(liquidityProviderCaps[msg.sender] >= assets, "ARM: LP cap exceeded");
        // total assets has already been updated with the new assets
        require(totalAssetsCap >= totalAssets(), "ARM: Total assets cap exceeded");

        // Save the new LP cap to storage
        liquidityProviderCaps[msg.sender] -= assets;
    }

    /// @dev Adds assets to the liquidity provider's cap when withdrawing assets or redeeming shares.
    /// Will not revert if the total assets cap is less than the total assets.
    function _postWithdrawHook(uint256 assets) internal virtual override {
        liquidityProviderCaps[msg.sender] += assets;
    }

    function setLiquidityProviderCap(address liquidityProvider, uint256 cap) external onlyOwner {
        liquidityProviderCaps[liquidityProvider] = cap;

        emit LiquidityProviderCap(liquidityProvider, cap);
    }

    /// @notice Set the total assets cap for a liquidity provider.
    /// Setting to zero will prevent any further deposits. The lp can still withdraw assets.
    function setTotalAssetsCap(uint256 _totalAssetsCap) external onlyOwner {
        totalAssetsCap = _totalAssetsCap;

        emit TotalAssetsCap(_totalAssetsCap);
    }
}
