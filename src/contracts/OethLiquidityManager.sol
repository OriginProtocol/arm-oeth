// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableOperable} from "./OwnableOperable.sol";
import {IOETHVault} from "./Interfaces.sol";

contract OethLiquidityManager is OwnableOperable {
    IOETHVault public constant vault =
        IOETHVault(0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab);

    /**
     * @notice Request withdrawal of WETH from OETH Vault.
     */
    function requestWithdrawal(
        uint256 amount
    ) external onlyOperatorOrOwner returns (uint256 requestId, uint256 queued) {
        return vault.requestWithdrawal(amount);
    }

    /**
     * @notice Claim previously requested withdrawal of WETH from OETH Vault.
     * The Vault's claimable WETH needs to be greater than or equal to the queued amount of the request.
     */
    function claimWithdrawal(uint256 requestId) external onlyOperatorOrOwner {
        vault.claimWithdrawal(requestId);
    }
}
