// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "contracts/Interfaces.sol";
import {ERC20, MockERC4626} from "@solmate/test/utils/mocks/MockERC4626.sol";

contract MockWstETH is MockERC4626 {
    ERC20 public immutable stETH;

    constructor(IERC20 _stETH) MockERC4626(ERC20(address(_stETH)), "Wrapped liquid staked Ether 2.0", "wstETH") {
        stETH = ERC20(address(_stETH));
    }

    function wrap(uint256 stETHAmount) external returns (uint256 wstETHAmount) {
        wstETHAmount = deposit(stETHAmount, msg.sender);
    }

    function unwrap(uint256 wstETHAmount) external returns (uint256 stETHAmount) {
        stETHAmount = redeem(wstETHAmount, msg.sender, msg.sender);
    }

    function getStETHByWstETH(uint256 wstETHAmount) external view returns (uint256 stETHAmount) {
        stETHAmount = convertToAssets(wstETHAmount);
    }

    function getWstETHByStETH(uint256 stETHAmount) external view returns (uint256 wstETHAmount) {
        wstETHAmount = convertToShares(stETHAmount);
    }

    /// @notice Returns stETH per 1 wstETH. For example, 1e18 = 1 stETH per wstETH.
    function stEthPerToken() external view returns (uint256) {
        return convertToAssets(1e18);
    }

    /// @notice Returns wstETH per 1 stETH. For example, 1e18 = 1 wstETH per stETH.
    function tokensPerStEth() external view returns (uint256) {
        return convertToShares(1e18);
    }
}
