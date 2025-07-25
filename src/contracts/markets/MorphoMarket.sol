// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IDistributionManager, SiloIncentivesControllerGaugeLike} from "../Interfaces.sol";
import {Abstract4626MarketWrapper} from "./Abstract4626MarketWrapper.sol";

/**
 * @title Morpho lending market wrapper so rewards can be collected.
 * @author Origin Protocol Inc
 */
contract MorphoMarket is Abstract4626MarketWrapper {
    /// @notice The address of the Morpho Token contract.
    IERC20 public constant MORPHO_TOKEN = IERC20(0x58D97B57BB95320F9a05dC918Aef65434969c2B2);

    /// @notice Constructor to set immutable storage variables.
    /// @param _arm The address of the ARM contract.
    /// @param _market The address of the Silo lending market.
    constructor(address _arm, address _market) Abstract4626MarketWrapper(_arm, _market) {}

    /// @notice Claim all Morpho tokens and send them to the Harvester.
    function _collectRewards() internal override returns (address[] memory, uint256[] memory) {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(MORPHO_TOKEN);
        amounts[0] = MORPHO_TOKEN.balanceOf(address(this));

        if (amounts[0] > 0) {
            // Transfer the Morpho tokens to the Harvester
            MORPHO_TOKEN.transfer(harvester, amounts[0]);
        }

        emit CollectedRewards(tokens, amounts);

        return (tokens, amounts);
    }
}
