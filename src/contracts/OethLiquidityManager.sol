// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {OwnableOperable} from "./OwnableOperable.sol";
import {IERC20, IOETHVault} from "./Interfaces.sol";

/**
 * @title Manages OETH liquidity against the OETH Vault.
 * @author Origin Protocol Inc
 */
contract OethLiquidityManager is OwnableOperable {
    address public immutable oeth;
    address public immutable oethVault;

    /// @param _oeth The address of the OETH token.
    /// @param _oethVault The address of the OETH Vault proxy.
    constructor(address _oeth, address _oethVault) {
        oeth = _oeth;
        oethVault = _oethVault;
    }

    /**
     * @notice Approve the OETH Vault to transfer OETH from this cont4act.
     */
    function approvals() external onlyOwner {
        _approvals();
    }

    function _approvals() internal {
        IERC20(oeth).approve(oethVault, type(uint256).max);
    }

    /**
     * @notice Request withdrawal of WETH from the OETH Vault.
     * @param amount The amount of OETH to burn and WETH to withdraw.
     */
    function requestWithdrawal(uint256 amount)
        external
        onlyOperatorOrOwner
        returns (uint256 requestId, uint256 queued)
    {
        return IOETHVault(oethVault).requestWithdrawal(amount);
    }

    /**
     * @notice Claim previously requested withdrawal of WETH from the OETH Vault.
     * The Vault's claimable WETH needs to be greater than or equal to the queued amount of the request.
     * @param requestId The ID of the OETH Vault's withdrawal request.
     */
    function claimWithdrawal(uint256 requestId) external onlyOperatorOrOwner {
        IOETHVault(oethVault).claimWithdrawal(requestId);
    }

    /**
     * @notice Claim multiple previously requested withdrawals of WETH from the OETH Vault.
     * The Vault's claimable WETH needs to be greater than or equal to the queued amount of the request.
     * @param requestIds List of request IDs from the OETH Vault's withdrawal requests.
     */
    function claimWithdrawals(uint256[] memory requestIds) external onlyOperatorOrOwner {
        IOETHVault(oethVault).claimWithdrawals(requestIds);
    }
}
