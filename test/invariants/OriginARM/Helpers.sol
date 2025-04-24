// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Setup} from "./Setup.sol";
import {Logger} from "test/invariants/OriginARM/Logger.sol";

abstract contract Helpers is Setup, Logger {
    function getRandom(address[] memory users, uint256 seed) public pure returns (address) {
        // Get a random user from the list of users
        return users[seed % users.length];
    }

    function getRandomLPs(uint8 seed) public view returns (address) {
        // Get a random user from the list of lps
        return lps[seed % lps.length];
    }

    function getRandomLPs(uint8 seed, bool withBalance) public view returns (address) {
        // Get a random user from the list of lps
        return withBalance ? getRandomLPsWithBalance(seed) : lps[seed % lps.length];
    }

    function getRandomLPsWithBalance(uint8 seed) public view returns (address) {
        return getRandomLPsWithBalance(seed, 0);
    }

    function getRandomLPsWithBalance(uint8 seed, uint256 minBalance) public view returns (address) {
        // Get a random user from the list of lps with a balance
        uint256 len = lps.length;
        for (uint256 i; i < len; i++) {
            address user_ = lps[(seed + i) % len];
            if (originARM.balanceOf(user_) > minBalance) {
                return user_;
            }
        }
        return address(0);
    }
}
