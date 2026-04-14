// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {Id, MarketParams} from "../IMorpho.sol";

library MarketParamsLib {
    uint256 internal constant MARKET_PARAMS_BYTES_LENGTH = 5 * 32;

    function id(MarketParams memory marketParams) internal pure returns (Id marketParamsId) {
        assembly ("memory-safe") {
            marketParamsId := keccak256(marketParams, MARKET_PARAMS_BYTES_LENGTH)
        }
    }
}
