// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {MultiLP} from "./MultiLP.sol";
import {ILiquidityProviderController} from "./Interfaces.sol";

/**
 * @title ARM integration to the Liquidity Provider Controller that whitelists liquidity providers
 * and enforces a total assets cap.
 * @author Origin Protocol Inc
 */
abstract contract LiquidityProviderControllerARM is MultiLP {
    address public liquidityProviderController;

    uint256[49] private _gap;

    event LiquidityProviderControllerUpdated(address indexed liquidityProviderController);

    /// @dev called in the ARM's initialize function to set the Liquidity Provider Controller
    function _initLPControllerARM(address _liquidityProviderController) internal {
        liquidityProviderController = _liquidityProviderController;

        emit LiquidityProviderControllerUpdated(_liquidityProviderController);
    }

    /// @dev calls the liquidity provider controller if one is configured to check the liquidity provider and total assets caps
    function _postDepositHook(uint256 assets) internal virtual override {
        if (liquidityProviderController != address(0)) {
            ILiquidityProviderController(liquidityProviderController).postDepositHook(msg.sender, assets);
        }
    }

    /// @notice Set the Liquidity Provider Controller contract address.
    /// Set to a zero address to disable the controller.
    function setLiquidityProviderController(address _liquidityProviderController) external onlyOwner {
        liquidityProviderController = _liquidityProviderController;

        emit LiquidityProviderControllerUpdated(_liquidityProviderController);
    }
}
