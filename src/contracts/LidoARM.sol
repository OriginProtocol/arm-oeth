// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {AbstractARM} from "./AbstractARM.sol";
import {LidoLiquidityManager} from "./LidoLiquidityManager.sol";

/**
 * @title Lido (stETH) Application Redemption Manager (ARM)
 * @dev This implementation supports multiple Liquidity Providers (LPs) with single buy and sell prices.
 * It also integrates to a LiquidityProviderController contract that caps the amount of assets a liquidity provider
 * can deposit and caps the ARM's total assets.
 * A performance fee is also collected on increases in the ARM's total assets.
 * @author Origin Protocol Inc
 */
contract LidoARM is Initializable, AbstractARM, LidoLiquidityManager {
    /// @param _steth The address of the stETH token
    /// @param _weth The address of the WETH token
    /// @param _lidoWithdrawalQueue The address of the Lido's withdrawal queue contract
    constructor(address _steth, address _weth, address _lidoWithdrawalQueue)
        AbstractARM(_steth, _weth, _weth)
        LidoLiquidityManager(_steth, _weth, _lidoWithdrawalQueue)
    {}

    /// @notice Initialize the storage variables stored in the proxy contract.
    /// The deployer that calls initialize has to approve the this ARM's proxy contract to transfer 1e12 WETH.
    /// @param _name The name of the liquidity provider (LP) token.
    /// @param _symbol The symbol of the liquidity provider (LP) token.
    /// @param _operator The address of the account that can request and claim Lido withdrawals.
    /// @param _fee The performance fee that is collected by the feeCollector measured in basis points (1/100th of a percent).
    /// 10,000 = 100% performance fee
    /// 1,500 = 15% performance fee
    /// @param _feeCollector The account that can collect the performance fee
    /// @param _liquidityProviderController The address of the Liquidity Provider Controller
    function initialize(
        string calldata _name,
        string calldata _symbol,
        address _operator,
        uint256 _fee,
        address _feeCollector,
        address _liquidityProviderController
    ) external initializer {
        _initARM(_operator, _name, _symbol, _fee, _feeCollector, _liquidityProviderController);
        _initLidoLiquidityManager();
    }

    /**
     * @dev Due to internal stETH mechanics required for rebasing support, in most cases stETH transfers are performed
     * for the value of 1 wei less than passed to transfer method. Larger transfer amounts can be 2 wei less.
     *
     * The MultiLP implementation ensures any WETH reserved for the withdrawal queue is not used in swaps from stETH to WETH.
     */
    function _transferAsset(address asset, address to, uint256 amount) internal override {
        // Add 2 wei if transferring stETH
        uint256 transferAmount = asset == address(token0) ? amount + 2 : amount;

        super._transferAsset(asset, to, transferAmount);
    }

    /**
     * @dev Calculates the amount of stETH in the Lido Withdrawal Queue.
     */
    function _externalWithdrawQueue() internal view override(AbstractARM, LidoLiquidityManager) returns (uint256) {
        return LidoLiquidityManager._externalWithdrawQueue();
    }
}
