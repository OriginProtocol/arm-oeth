// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {OwnableOperable} from "./OwnableOperable.sol";
import {ILiquidityProviderARM} from "./Interfaces.sol";

/**
 * @title Manages capital limits of an Automated Redemption Manager (ARM).
 * Caps the total assets and individual liquidity provider assets.
 * @author Origin Protocol Inc
 */
contract CapManager is Initializable, OwnableOperable {
    /// @notice The address of the linked Automated Redemption Manager (ARM).
    address public immutable arm;

    /// @notice true if a cap is placed on each liquidity provider's account.
    bool public accountCapEnabled;
    /// @notice The ARM's maximum allowed total assets.
    uint248 public totalAssetsCap;
    /// @notice The maximum allowed assets for each liquidity provider.
    /// This is effectively a whitelist of liquidity providers as a zero amount prevents any deposits.
    mapping(address liquidityProvider => uint256 cap) public liquidityProviderCaps;

    uint256[48] private _gap;

    event LiquidityProviderCap(address indexed liquidityProvider, uint256 cap);
    event TotalAssetsCap(uint256 cap);
    event AccountCapEnabled(bool enabled);

    constructor(address _arm) {
        arm = _arm;
    }

    function initialize(address _operator) external initializer {
        _initOwnableOperable(_operator);
        accountCapEnabled = false;
    }

    function postDepositHook(address liquidityProvider, uint256 assets) external {
        require(msg.sender == arm, "LPC: Caller is not ARM");

        // total assets has already been updated with the new assets
        require(totalAssetsCap >= ILiquidityProviderARM(arm).totalAssets(), "LPC: Total assets cap exceeded");

        if (!accountCapEnabled) return;

        uint256 oldCap = liquidityProviderCaps[liquidityProvider];
        require(oldCap >= assets, "LPC: LP cap exceeded");

        uint256 newCap = oldCap - assets;

        // Save the new LP cap to storage
        liquidityProviderCaps[liquidityProvider] = newCap;

        emit LiquidityProviderCap(liquidityProvider, newCap);
    }

    function setLiquidityProviderCaps(address[] calldata _liquidityProviders, uint256 cap)
        external
        onlyOperatorOrOwner
    {
        for (uint256 i = 0; i < _liquidityProviders.length; i++) {
            liquidityProviderCaps[_liquidityProviders[i]] = cap;

            emit LiquidityProviderCap(_liquidityProviders[i], cap);
        }
    }

    /// @notice Set the ARM's maximum total assets.
    /// Setting to zero will prevent any further deposits.
    /// The liquidity provider can still withdraw assets.
    function setTotalAssetsCap(uint248 _totalAssetsCap) external onlyOperatorOrOwner {
        totalAssetsCap = _totalAssetsCap;

        emit TotalAssetsCap(_totalAssetsCap);
    }

    /// @notice Enable or disable the account cap.
    function setAccountCapEnabled(bool _accountCapEnabled) external onlyOwner {
        require(accountCapEnabled != _accountCapEnabled, "LPC: Account cap already set");

        accountCapEnabled = _accountCapEnabled;

        emit AccountCapEnabled(_accountCapEnabled);
    }
}
