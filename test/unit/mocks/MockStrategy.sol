// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "contracts/Interfaces.sol";
import {IStrategy} from "contracts/Interfaces.sol";

contract MockStrategy is IStrategy {
    IERC20 public token;

    constructor(IERC20 _token) {
        token = _token;
    }

    function checkBalance(address) external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function deposit(address _asset, uint256 _amount) external {}

    function depositAll() external {}

    function withdraw(address _recipient, address, uint256 _amount) external {
        token.transfer(_recipient, _amount);
    }

    function withdrawAll() external {
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function supportsAsset(address _token) external view returns (bool) {
        return address(token) == _token;
    }

    function collectRewardTokens() external {}

    function getRewardTokenAddresses() external view returns (address[] memory) {}
}
