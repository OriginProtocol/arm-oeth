// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IIrm} from "contracts/morpho/IIrm.sol";
import {MarketParams, Market} from "contracts/morpho/IMorpho.sol";

contract MockMorphoIrm is IIrm {
    uint256 public borrowRatePerSecond;

    function setBorrowRatePerSecond(uint256 borrowRatePerSecond_) external {
        borrowRatePerSecond = borrowRatePerSecond_;
    }

    function borrowRate(MarketParams memory, Market memory) external view returns (uint256) {
        return borrowRatePerSecond;
    }

    function borrowRateView(MarketParams memory, Market memory) external view returns (uint256) {
        return borrowRatePerSecond;
    }
}
