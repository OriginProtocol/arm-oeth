// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Base_Test_} from "test/Base.sol";

contract Helpers is Base_Test_ {
    function randomAddrDiff(address _addr) public returns (address) {
        address _rand = vm.randomAddress();
        while (_rand == _addr) {
            _rand = vm.randomAddress();
        }
        return _rand;
    }

    function randomAddrDiff(address _addr1, address _addr2) public returns (address) {
        address _rand = vm.randomAddress();
        while (_rand == _addr1 || _rand == _addr2) {
            _rand = vm.randomAddress();
        }
        return _rand;
    }

    function abs(int256 x) public pure returns (uint256) {
        return x < 0 ? uint256(-x) : uint256(x);
    }
}
