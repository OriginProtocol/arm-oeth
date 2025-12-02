// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IStakedUSDe} from "./Interfaces.sol";

/**
 * @title A helper contract that allows the ARM to have multiple sUSDe cooldowns in parallel.
 * @author Origin Protocol Inc
 */
contract EthenaUnstaker {
    /// The parent Ethena ARM contract
    address public immutable arm;
    /// @notice The address of Ethena's staked synthetic dollar token (sUSDe)
    IStakedUSDe public immutable susde;

    constructor(address _arm, IStakedUSDe _susde) {
        arm = _arm;
        susde = _susde;
    }

    /// @notice Request a cooldown of USDe from Ethena's Staked USDe (sUSDe) contract.
    /// @param sUSDeAmount The amount of staked USDe (sUSDe) to withdraw.
    /// @return usde The amount of underlying USDe that will be withdrawable after the cooldown period.
    function requestUnstake(uint256 sUSDeAmount) external returns (uint256 usde) {
        require(msg.sender == arm, "Only ARM can request unstake");
        usde = susde.cooldownShares(sUSDeAmount);
    }

    /// @notice Claim the underlying USDe after the cooldown period has ended and send to the ARM.
    /// Reverts with `InvalidCooldown` from the Staked USDe contract if the cooldown period has not yet passed.
    function claimUnstake() external {
        require(msg.sender == arm, "Only ARM can request unstake");
        susde.unstake(arm);
    }
}
