// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {AbstractARM} from "./AbstractARM.sol";
import {LiquidityProviderControllerARM} from "./LiquidityProviderControllerARM.sol";
import {FixedPriceARM} from "./FixedPriceARM.sol";
import {LidoLiquidityManager} from "./LidoLiquidityManager.sol";
import {MultiLP} from "./MultiLP.sol";
import {PerformanceFee} from "./PerformanceFee.sol";

/**
 * @title Lido (stETH) Application Redemption Manager (ARM)
 * @dev This implementation supports multiple Liquidity Providers (LPs) with single buy and sell prices.
 * @author Origin Protocol Inc
 */
contract LidoFixedPriceMultiLpARM is
    Initializable,
    MultiLP,
    PerformanceFee,
    LiquidityProviderControllerARM,
    FixedPriceARM,
    LidoLiquidityManager
{
    /// @param _stEth The address of the stETH token
    /// @param _weth The address of the WETH token
    /// @param _lidoWithdrawalQueue The address of the Lido's withdrawal queue contract
    constructor(address _stEth, address _weth, address _lidoWithdrawalQueue)
        AbstractARM(_stEth, _weth)
        MultiLP(_weth)
        FixedPriceARM()
        LidoLiquidityManager(_stEth, _weth, _lidoWithdrawalQueue)
    {}

    /// @notice Initialize the contract.
    /// @param _name The name of the liquidity provider (LP) token.
    /// @param _symbol The symbol of the liquidity provider (LP) token.
    /// @param _operator The address of the account that can request and claim Lido withdrawals.
    /// @param _fee The performance fee that is collected by the feeCollector measured in basis points (1/100th of a percent).
    /// 10,000 = 100% performance fee
    /// 500 = 5% performance fee
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
        _initOwnableOperable(_operator);
        _initMultiLP(_name, _symbol);
        _initPerformanceFee(_fee, _feeCollector);
        _initLPControllerARM(_liquidityProviderController);
    }

    /**
     * @dev Due to internal stETH mechanics required for rebasing support,
     * in most cases stETH transfers are performed for the value of 1 wei less than passed to transfer method.
     * Larger transfer amounts can be 2 wei less.
     *
     * The MultiLP implementation ensures any WETH reserved for the withdrawal queue is no used in swaps from stETH to WETH.
     */
    function _transferAsset(address asset, address to, uint256 amount) internal override(AbstractARM, MultiLP) {
        // Add 2 wei if transferring stETH
        uint256 transferAmount = asset == address(token0) ? amount + 2 : amount;

        MultiLP._transferAsset(asset, to, transferAmount);
    }

    /// @dev Funds the ARM's withdrawal queue when swaps send WETH to the ARM
    function _transferAssetFrom(address asset, address from, address to, uint256 amount)
        internal
        override(AbstractARM, MultiLP)
    {
        MultiLP._transferAssetFrom(asset, from, to, amount);
    }

    function _externalWithdrawQueue() internal view override(MultiLP, LidoLiquidityManager) returns (uint256) {
        return LidoLiquidityManager._externalWithdrawQueue();
    }

    function _postDepositHook(uint256 assets)
        internal
        override(MultiLP, LiquidityProviderControllerARM, PerformanceFee)
    {
        // Store the new total assets after the deposit and performance fee accrued
        PerformanceFee._postDepositHook(assets);

        // Check the LP can deposit the assets
        LiquidityProviderControllerARM._postDepositHook(assets);
    }

    function _postWithdrawHook(uint256 assets) internal override(MultiLP, PerformanceFee) {
        // Store the new total assets after the withdrawal and performance fee accrued
        PerformanceFee._postWithdrawHook(assets);
    }

    function _postClaimHook(uint256 assets) internal override {
        // do nothing
    }

    function totalAssets() public view override(MultiLP, PerformanceFee) returns (uint256) {
        return PerformanceFee.totalAssets();
    }
}
