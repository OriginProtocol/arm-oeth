// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {AbstractARM} from "./AbstractARM.sol";
import {FixedPriceARM} from "./FixedPriceARM.sol";
import {LidoLiquidityManager} from "./LidoLiquidityManager.sol";
import {MultiLP} from "./MultiLP.sol";
import {PerformanceFee} from "./PerformanceFee.sol";

contract LidoFixedPriceMultiLpARM is Initializable, MultiLP, PerformanceFee, FixedPriceARM, LidoLiquidityManager {
    /// @param _stEth The address of the stETH token
    /// @param _weth The address of the WETH token
    /// @param _lidoWithdrawalQueue The address of the stETH Withdrawal contract
    constructor(address _stEth, address _weth, address _lidoWithdrawalQueue)
        AbstractARM(_stEth, _weth)
        MultiLP(_weth)
        FixedPriceARM()
        LidoLiquidityManager(_stEth, _weth, _lidoWithdrawalQueue)
    {}

    /// @notice Initialize the contract.
    /// @param _name The name of the liquidity provider (LP) token.
    /// @param _symbol The symbol of the liquidity provider (LP) token.
    /// @param _operator The address of the account that can request and claim OETH withdrawals.
    /// @param _fee The performance fee that is collected by the feeCollector measured in basis points (1/100th of a percent).
    /// 10,000 = 100% performance fee
    /// 500 = 5% performance fee
    /// @param _feeCollector The account that receives the performance fee as shares
    function initialize(
        string calldata _name,
        string calldata _symbol,
        address _operator,
        uint256 _fee,
        address _feeCollector
    ) external initializer {
        _initOwnableOperable(_operator);
        _initMultiLP(_name, _symbol);
        _initPerformanceFee(_fee, _feeCollector);
    }

    /**
     * @notice Calculate transfer amount for outToken.
     * Due to internal stETH mechanics required for rebasing support,
     * in most cases stETH transfers are performed for the value of 1 wei less than passed to transfer method.
     * Larger transfer amounts can be 2 wei less.
     */
    function _calcTransferAmount(address outToken, uint256 amount)
        internal
        view
        override
        returns (uint256 transferAmount)
    {
        // Add 2 wei if transferring stETH
        transferAmount = outToken == address(token0) ? amount + 2 : amount;
    }

    function _assetsInWithdrawQueue() internal view override(MultiLP, LidoLiquidityManager) returns (uint256) {
        return LidoLiquidityManager._assetsInWithdrawQueue();
    }

    function _postDepositHook(uint256 assets) internal override {
        // do nothing
    }

    function _postWithdrawHook(uint256 assets) internal override {
        // do nothing
    }

    function _postClaimHook(uint256 assets) internal override {
        // do nothing
    }

    function totalAssets() public view override(MultiLP, PerformanceFee) returns (uint256) {
        return PerformanceFee.totalAssets();
    }
}
