// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AbstractARM} from "./AbstractARM.sol";
import {IERC20} from "./Interfaces.sol";

abstract contract PeggedARM is AbstractARM {
    function _swap(IERC20 inToken, IERC20 outToken, uint256 amount, address to) internal override {
        require(inToken == token0 && outToken == token1, "ARM: Invalid swap");

        // Transfer the input tokens from the caller to this ARM contract
        require(inToken.transferFrom(msg.sender, address(this), amount), "failed transfer in");

        // Transfer the same amount of output tokens to the recipient
        require(outToken.transfer(to, amount), "failed transfer out");
    }
}
