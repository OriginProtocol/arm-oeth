// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC20} from "@solmate/tokens/ERC20.sol";

contract MockWstETH is ERC20 {
    ERC20 public immutable steth;

    constructor(address _steth) ERC20("Wrapped liquid staked Ether 2.0", "wstETH", 18) {
        steth = ERC20(_steth);
    }

    function wrap(uint256 stETHAmount) external returns (uint256 wstETHAmount) {
        steth.transferFrom(msg.sender, address(this), stETHAmount);
        wstETHAmount = stETHAmount;
        _mint(msg.sender, wstETHAmount);
    }

    function unwrap(uint256 wstETHAmount) external returns (uint256 stETHAmount) {
        _burn(msg.sender, wstETHAmount);
        stETHAmount = wstETHAmount;
        steth.transfer(msg.sender, stETHAmount);
    }

    function getStETHByWstETH(uint256 wstETHAmount) external pure returns (uint256 stETHAmount) {
        stETHAmount = wstETHAmount;
    }

    function getWstETHByStETH(uint256 stETHAmount) external pure returns (uint256 wstETHAmount) {
        wstETHAmount = stETHAmount;
    }
}
