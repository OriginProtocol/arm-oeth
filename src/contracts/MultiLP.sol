// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20, ERC20Upgradeable} from "@openzeppelin/contracts/token/ERC20/ERC20Upgradeable.sol";

import {AbstractARM} from "./AbstractARM.sol";
import {IERC20, IOETHVault} from "./Interfaces.sol";

abstract contract MultiLP is AbstractARM, ERC20Upgradeable {
    address public immutable liquidityToken;

    constructor(address _liquidityToken) {
        liquidityToken = _liquidityToken;
    }

    function _initialize(string _name, string _symbol) external {
        __ERC20_init(_name, _symbol);
    }

    function deposit(uint256 amount) external returns (uint256 shares) {
        uint256 totalAssets = IERC20(token0).balanceOf(address(this)) + IERC20(token1).balanceOf(address(this));

        shares = (totalAssets == 0) ? amount : (amount * totalSupply()) / totalAssets;

        // Transfer the liquidity token from the sender to this contract
        IERC20(liquidityToken).transferFrom(msg.sender, address(this), amount);

        // mint shares
        _mint(msg.sender, shares);
    }
}
