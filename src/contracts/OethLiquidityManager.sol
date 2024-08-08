// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableOperable} from "./OwnableOperable.sol";
import {IERC20, IOETHVault} from "./Interfaces.sol";

contract OethLiquidityManager is OwnableOperable {
    address public immutable oeth;
    address public immutable oethVault;

    /// @param _oethVault The address of the OETH Vault proxy.
    constructor(address _oeth, address _oethVault) {
        oeth = _oeth;
        oethVault = _oethVault;
    }

    /**
     * @notice Approve the OETH Vault to transfer OETH from the ARM.
     */
    function approvals() external onlyOwner {
        _approvals();
    }

    function _approvals() internal {
        IERC20(oeth).approve(address(oethVault), type(uint256).max);
    }

    /**
     * @notice Request withdrawal of WETH from OETH Vault.
     */
    function requestWithdrawal(uint256 amount)
        external
        onlyOperatorOrOwner
        returns (uint256 requestId, uint256 queued)
    {
        return IOETHVault(oethVault).requestWithdrawal(amount);
    }

    /**
     * @notice Claim previously requested withdrawal of WETH from OETH Vault.
     * The Vault's claimable WETH needs to be greater than or equal to the queued amount of the request.
     */
    function claimWithdrawal(uint256 requestId) external onlyOperatorOrOwner {
        IOETHVault(oethVault).claimWithdrawal(requestId);
    }

    function claimWithdrawals(uint256[] memory requestIds) external onlyOperatorOrOwner {
        IOETHVault(oethVault).claimWithdrawals(requestIds);
    }
}
