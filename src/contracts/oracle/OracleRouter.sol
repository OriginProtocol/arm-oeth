// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

// Interfaces
import {AggregatorV3Interface} from "contracts/Interfaces.sol";

// OZ Libraries
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title OracleRouter
/// @notice This contract is used to fetch the price of an asset from a price feed.
/// @author Origin Protocol
contract OracleRouter {
    using SafeCast for int256;

    /// @notice Address of the fixed price feed, used to indicate a fixed price
    address internal constant FIXED_PRICE = address(0x1);

    /// @notice Maximum allowed staleness buffer above normal Oracle maximum staleness
    uint256 internal constant STALENESS_BUFFER = 1 days;

    /// @notice Returns the total price in 18 digit units for a given asset. This implementation
    ///         does not (!) do range checks as the parent OracleRouter does.
    /// @param asset address of the asset
    /// @return uint256 unit price for 1 asset unit, in 18 decimal fixed
    function price(address asset) external view virtual returns (uint256) {
        (address _feed, uint256 maxStaleness) = feedMetadata(asset);
        if (_feed == FIXED_PRICE) {
            return 1e18;
        }
        require(_feed != address(0), "Asset not available");

        (, int256 _iprice,, uint256 updatedAt,) = AggregatorV3Interface(_feed).latestRoundData();

        require(updatedAt + maxStaleness >= block.timestamp, "Oracle price too old");

        uint8 decimals = AggregatorV3Interface(_feed).decimals();
        return scaleBy(_iprice.toUint256(), 18, decimals);
    }

    /// @notice Returns the price feed address and maximum staleness for a given asset.
    /// @param asset address of the asset
    /// @return feedAddress address of the price feed
    /// @return maxStaleness maximum staleness for the price feed
    function feedMetadata(address asset) internal view virtual returns (address feedAddress, uint256 maxStaleness) {
        if (asset == 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38) {
            // FIXED_PRICE: WS/S
            feedAddress = FIXED_PRICE;
        } else {
            revert("Asset not available");
        }
    }

    /// @notice Scales a number from one decimal representation to another.
    /// @param x number to scale
    /// @param to target decimal representation
    /// @param from source decimal representation
    /// @return scaled number in target decimal representation
    function scaleBy(uint256 x, uint256 to, uint256 from) internal pure returns (uint256) {
        if (from > to) {
            return x / (10 ** (from - to));
        } else if (from < to) {
            return x * (10 ** (to - from));
        } else {
            return x;
        }
    }
}
