// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {AggregatorV3Interface} from "contracts/Interfaces.sol";

contract OracleRouter {
    address internal constant FIXED_PRICE = address(0x1);
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
        uint256 _price = scaleBy(uint256(_iprice), 18, decimals);
        return _price;
    }

    function feedMetadata(address asset) internal view virtual returns (address feedAddress, uint256 maxStaleness) {
        if (asset == 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38) {
            // FIXED_PRICE WS/S
            feedAddress = FIXED_PRICE;
            maxStaleness = 0;
        } else {
            revert("Asset not available");
        }
    }

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
