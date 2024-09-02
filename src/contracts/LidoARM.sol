// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AbstractARM} from "./AbstractARM.sol";
import {FixedPriceARM} from "./FixedPriceARM.sol";
import {LidoLiquidityManager} from "./LidoLiquidityManager.sol";
import {OwnerLP} from "./OwnerLP.sol";
import {Initializable} from "./utils/Initializable.sol";

contract LidoARM is Initializable, OwnerLP, FixedPriceARM, LidoLiquidityManager {
    /// @param _stEth The address of the stETH token
    /// @param _weth The address of the WETH token
    /// @param _stEthWithdrawal The address of the stETH Withdrawal contract
    constructor(address _stEth, address _weth, address _stEthWithdrawal)
        AbstractARM(_stEth, _weth)
        FixedPriceARM()
        LidoLiquidityManager(_stEth, _weth, _stEthWithdrawal)
    {}

    /// @notice Initialize the contract.
    /// @param _operator The address of the account that can request and claim OETH withdrawals.
    function initialize(address _operator) external initializer {
        _setOperator(_operator);
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
}
