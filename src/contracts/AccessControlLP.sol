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
        uint256 oldCap = liquidityProviderCaps[msg.sender];
        require(oldCap >= assets, "ARM: LP cap exceeded");
        // total assets has already been updated with the new assets
        require(totalAssetsCap >= totalAssets(), "ARM: Total assets cap exceeded");

        uint256 newCap = oldCap - assets;

        // Save the new LP cap to storage
        liquidityProviderCaps[msg.sender] = newCap;

        emit LiquidityProviderCap(msg.sender, newCap);
    }

    function setLiquidityProviderCaps(address[] calldata _liquidityProviders, uint256 cap) external onlyOwner {
        for (uint256 i = 0; i < _liquidityProviders.length; i++) {
            liquidityProviderCaps[_liquidityProviders[i]] = cap;

            emit LiquidityProviderCap(_liquidityProviders[i], cap);
        }
    }

    /// @notice Set the total assets cap for a liquidity provider.
    /// Setting to zero will prevent any further deposits. The lp can still withdraw assets.
    function setTotalAssetsCap(uint256 _totalAssetsCap) external onlyOwner {
        totalAssetsCap = _totalAssetsCap;

        emit TotalAssetsCap(_totalAssetsCap);
    }
}
