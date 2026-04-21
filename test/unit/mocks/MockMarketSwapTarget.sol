// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "contracts/Interfaces.sol";

contract MockMarketSwapTarget {
    function executeSwap(address tokenIn, address recipient, uint256 amountIn) external {
        IERC20(tokenIn).transfer(recipient, amountIn);
    }

    function revertSwap() external pure {
        revert("MockMarketSwapTarget: revert");
    }
}
