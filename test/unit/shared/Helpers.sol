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
}
