// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PeggedARM} from "./PeggedARM.sol";
import {OethLiquidityManager} from "./OethLiquidityManager.sol";
import {Initializable} from "./utils/Initializable.sol";

contract OEthARM is Initializable, PeggedARM, OethLiquidityManager {
    /// @param _oeth The address of the OETH token that is being swapped into this contract.
    /// @param _weth The address of the WETH token that is being swapped out of this contract.
    /// @param _oethVault The address of the OETH Vault proxy.
    constructor(address _oeth, address _weth, address _oethVault)
        PeggedARM(_oeth, _weth)
        OethLiquidityManager(_oeth, _oethVault)
    {}

    /// @notice Initialize the contract.
    /// @param _operator The address of the account that can request and claim OETH withdrawals.
    function initialize(address _operator) external initializer {
        _setOperator(_operator);
        _approvals();
    }
}
