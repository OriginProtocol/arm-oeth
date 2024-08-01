// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableOperable} from "./OwnableOperable.sol";
import {IOETHVault} from "./Interfaces.sol";

contract OethLiquidityManager is OwnableOperable {
    address public immutable oethVault;

    /// @param _oethVault The address of the OETH Vault proxy.
    constructor(address _oethVault) {
        oethVault = _oethVault;
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
