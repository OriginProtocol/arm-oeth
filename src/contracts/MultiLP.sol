// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {AbstractARM} from "./AbstractARM.sol";
import {IERC20, IOETHVault} from "./Interfaces.sol";

abstract contract MultiLP is ERC20 {
    address public immutable liquidityToken;

    constructor(address _liquidityToken) {
        liquidityToken = _liquidityToken;
    }

    function deposit(uint256 amount) external returns (uint256 shares) {
        uint256 totalAssets = IERC20(token0).balanceOf(address(this)) + IERC20(token1).balanceOf(address(this));

        shares = (totalAssets == 0) ? amount : (amount * totalSupply()) / totalAssets;

        // Transfer the liquidity token from the sender to this contract
        IERC20(liquidityToken).transferFrom(msg.sender, address(this), amount);

        // mint shares
    }
}
