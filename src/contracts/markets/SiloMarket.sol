// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IDistributionManager, SiloIncentivesControllerGaugeLike} from "../Interfaces.sol";
import {Abstract4626MarketWrapper} from "./Abstract4626MarketWrapper.sol";

/**
 * @title Silo lending market wrapper so rewards can be collected.
 * @author Origin Protocol Inc
 */
contract SiloMarket is Abstract4626MarketWrapper {
    /// @notice The address of the Silo gauge for the lending market.
    address public immutable gauge;

    /// @notice Constructor to set immutable storage variables.
    /// @param _arm The address of the ARM contract.
    /// @param _market The address of the Silo lending market.
    /// @param _gauge The address of the Silo gauge for the lending market.
    constructor(address _arm, address _market, address _gauge) Abstract4626MarketWrapper(_arm, _market) {
        require(_gauge != address(0), "Gauge not configured");
        gauge = _gauge;
    }

    /// @notice Claim all reward tokens from the Silo gauge and send them to the Harvester.
    function _collectRewards() internal override returns (address[] memory, uint256[] memory) {
        // Claim and send the rewards to the Harvester
        IDistributionManager.AccruedRewards[] memory data =
            SiloIncentivesControllerGaugeLike(gauge).claimRewards(harvester);

        uint256 length = data.length;
        address[] memory tokens = new address[](length);
        uint256[] memory amounts = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            tokens[i] = data[i].rewardToken;
            amounts[i] = data[i].amount;
        }

        emit CollectedRewards(tokens, amounts);

        return (tokens, amounts);
    }
}
