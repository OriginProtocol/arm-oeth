// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "./Ownable.sol";

contract OwnableOperable is Ownable {
    // keccak256(“eip1967.proxy.operator”) - 1, inspired by EIP 1967
    bytes32 internal constant OPERATOR_SLOT = 0x14cc265c8475c78633f4e341e72b9f4f0d55277c8def4ad52d79e69580f31482;

    event OperatorChanged(address newAdmin);

    constructor() {
        assert(OPERATOR_SLOT == bytes32(uint256(keccak256("eip1967.proxy.operator")) - 1));
    }

    function operator() external view returns (address) {
        return _operator();
    }

    /// @notice Set the account that can request and claim withdrawals.
    function setOperator(address newOperator) external onlyOwner {
        _setOperator(newOperator);
    }

    function _operator() internal view returns (address operatorOut) {
        bytes32 position = OPERATOR_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            operatorOut := sload(position)
        }
    }

    function _setOperator(address newOperator) internal {
        bytes32 position = OPERATOR_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(position, newOperator)
        }

        emit OperatorChanged(newOperator);
    }

    modifier onlyOperatorOrOwner() {
        require(
            msg.sender == _operator() || msg.sender == _owner(), "ARM: Only operator or owner can call this function."
        );
        _;
    }
}
