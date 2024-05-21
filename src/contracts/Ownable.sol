// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract Ownable {
    // keccak256(“eip1967.proxy.admin”) - per EIP 1967
    bytes32 internal constant OWNER_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    event AdminChanged(address previousAdmin, address newAdmin);

    constructor() {
        assert(OWNER_SLOT == bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1));
        _setOwner(msg.sender);
    }

    function owner() external view returns (address) {
        return _owner();
    }

    function setOwner(address newOwner) external onlyOwner {
        _setOwner(newOwner);
    }

    function _owner() internal view returns (address ownerOut) {
        bytes32 position = OWNER_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            ownerOut := sload(position)
        }
    }

    function _setOwner(address newOwner) internal {
        emit AdminChanged(_owner(), newOwner);
        bytes32 position = OWNER_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(position, newOwner)
        }
    }

    function _onlyOwner() internal view {
        require(msg.sender == _owner(), "ARM: Only owner can call this function.");
    }

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }
}
