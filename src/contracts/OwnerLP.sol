// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "./Ownable.sol";
import {IERC20} from "./Interfaces.sol";

abstract contract OwnerLP is Ownable {
    /**
     * @notice Owner can transfer out any ERC20 token.
     */
    function transferToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }
}
