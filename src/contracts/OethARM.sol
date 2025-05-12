// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {AbstractARM} from "./AbstractARM.sol";
import {PeggedARM} from "./PeggedARM.sol";
import {OwnerLP} from "./OwnerLP.sol";
import {OethLiquidityManager} from "./OethLiquidityManager.sol";

/**
 * @title Origin Ether (OETH) Automated Redemption Manager (ARM)
 * @author Origin Protocol Inc
 */
contract OethARM is Initializable, OwnerLP, PeggedARM, OethLiquidityManager {
    /// @param _oeth The address of the OETH token that is being swapped into this contract.
    /// @param _weth The address of the WETH token that is being swapped out of this contract.
    /// @param _oethVault The address of the OETH Vault proxy.
    constructor(address _oeth, address _weth, address _oethVault)
        AbstractARM(_oeth, _weth, _weth, 10 minutes, 0)
        PeggedARM(false)
        OethLiquidityManager(_oeth, _oethVault)
    {}

    /// @notice Initialize the contract.
    /// @param _operator The address of the account that can request and claim OETH withdrawals from the OETH Vault.
    function initialize(address _operator) external initializer {
        _setOperator(_operator);
        _approvals();
    }

    function _externalWithdrawQueue() internal view override returns (uint256 assets) {
        // TODO track OETH sent to the OETH Vault's withdrawal queue
    }
}
