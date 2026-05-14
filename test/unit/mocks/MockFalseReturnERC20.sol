// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

contract MockFalseReturnERC20 is MockERC20 {
    bool public transferReturnsFalse;
    bool public transferFromReturnsFalse;
    bool public approveReturnsFalse;

    constructor(string memory name, string memory symbol, uint8 decimals) MockERC20(name, symbol, decimals) {}

    function setTransferReturnsFalse(bool value) external {
        transferReturnsFalse = value;
    }

    function setTransferFromReturnsFalse(bool value) external {
        transferFromReturnsFalse = value;
    }

    function setApproveReturnsFalse(bool value) external {
        approveReturnsFalse = value;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        if (approveReturnsFalse) return false;
        return super.approve(spender, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (transferReturnsFalse) return false;
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (transferFromReturnsFalse) return false;
        return super.transferFrom(from, to, amount);
    }
}
