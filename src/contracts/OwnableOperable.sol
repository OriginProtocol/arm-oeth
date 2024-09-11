// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "./Ownable.sol";

contract OwnableOperable is Ownable {
    /// @notice The account that can request and claim withdrawals.
    address public operator;

    uint256[50] private _gap;

    event OperatorChanged(address newAdmin);

    function _initOwnableOperable(address _operator) internal {
        _setOperator(_operator);
    }

    /// @notice Set the account that can request and claim withdrawals.
    /// @param newOperator The address of the new operator.
    function setOperator(address newOperator) external onlyOwner {
        _setOperator(newOperator);
    }

    function _setOperator(address newOperator) internal {
        operator = newOperator;

        emit OperatorChanged(newOperator);
    }

    modifier onlyOperatorOrOwner() {
        require(msg.sender == operator || msg.sender == _owner(), "ARM: Only operator or owner can call this function.");
        _;
    }
}
