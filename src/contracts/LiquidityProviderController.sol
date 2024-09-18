// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "./Ownable.sol";
import {ILiquidityProviderARM} from "./Interfaces.sol";

/**
 * @title Controller of ARM liquidity providers.
 * @author Origin Protocol Inc
 */
contract LiquidityProviderController is Ownable {
    /// @notice The address of the linked Application Redemption Manager (ARM).
    address public immutable arm;

    /// @notice The ARM's maximum allowed total assets.
    uint256 public totalAssetsCap;
    /// @notice The maximum allowed assets for each liquidity provider.
    /// This is effectively a whitelist of liquidity providers as a zero amount prevents any deposits.
    mapping(address liquidityProvider => uint256 cap) public liquidityProviderCaps;

    uint256[48] private _gap;

    event LiquidityProviderCap(address indexed liquidityProvider, uint256 cap);
    event TotalAssetsCap(uint256 cap);

    constructor(address _arm) {
        arm = _arm;
    }

    function postDepositHook(address liquidityProvider, uint256 assets) external {
        require(msg.sender == arm, "LPC: Caller is not ARM");

        uint256 oldCap = liquidityProviderCaps[liquidityProvider];
        require(oldCap >= assets, "LPC: LP cap exceeded");

        // total assets has already been updated with the new assets
        require(totalAssetsCap >= ILiquidityProviderARM(arm).totalAssets(), "LPC: Total assets cap exceeded");

        uint256 newCap = oldCap - assets;

        // Save the new LP cap to storage
        liquidityProviderCaps[liquidityProvider] = newCap;

        emit LiquidityProviderCap(liquidityProvider, newCap);
    }

    function setLiquidityProviderCaps(address[] calldata _liquidityProviders, uint256 cap) external onlyOwner {
        for (uint256 i = 0; i < _liquidityProviders.length; i++) {
            liquidityProviderCaps[_liquidityProviders[i]] = cap;

            emit LiquidityProviderCap(_liquidityProviders[i], cap);
        }
    }

    /// @notice Set the ARM's maximum total assets.
    /// Setting to zero will prevent any further deposits.
    /// The liquidity provider can still withdraw assets.
    function setTotalAssetsCap(uint256 _totalAssetsCap) external onlyOwner {
        totalAssetsCap = _totalAssetsCap;

        emit TotalAssetsCap(_totalAssetsCap);
    }
}
