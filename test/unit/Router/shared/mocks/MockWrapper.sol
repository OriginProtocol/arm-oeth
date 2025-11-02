// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC20} from "@solmate/tokens/ERC20.sol";

contract MockWrapper is ERC20 {
    ERC20 public underlying;

    constructor(address _underlying)
        ERC20(
            string(abi.encode("Wrapped ", ERC20(_underlying).name())),
            string(abi.encode("W", ERC20(_underlying).symbol())),
            ERC20(_underlying).decimals()
        )
    {
        underlying = ERC20(_underlying);
    }

    function wrap(uint256 amount) external returns (uint256) {
        underlying.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
        return amount;
    }

    function unwrap(uint256 amount) external returns (uint256) {
        _burn(msg.sender, amount);
        underlying.transfer(msg.sender, amount);
        return amount;
    }

    function getWstETHByStETH(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function getStETHByWstETH(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function getWeETHByeETH(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function getEETHByWeETH(uint256 amount) external pure returns (uint256) {
        return amount;
    }
}
