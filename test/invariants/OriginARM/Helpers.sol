// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Setup} from "./Setup.sol";
import {Logger} from "test/invariants/OriginARM/Logger.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

abstract contract Helpers is Setup, Logger {
    uint256[] public originRequests;
    mapping(address => uint256[]) public requests;

    function getRandom(address[] memory array, uint256 seed) public pure returns (address) {
        // Get a random user from the list of array
        return array[seed % array.length];
    }

    function getRandomMarket(uint256 seed) public view returns (address, address) {
        address currentMarket = originARM.activeMarket();
        // If current market is not set, we can pick any market randomly
        if (currentMarket == address(0)) return (address(0), getRandom(markets, seed));

        // Create a copy of the markets array
        address[] memory _markets = markets;
        // Find the current market in the list and replace it with address(0)
        for (uint256 i; i < _markets.length; i++) {
            if (_markets[i] == currentMarket) {
                _markets[i] = address(0);
                break;
            }
        }

        // Now we are sure that the list of market doesn't have the current market
        // Get a random market from the list
        return (currentMarket, getRandom(_markets, seed));
    }

    function getRandomLPs(uint8 seed) public view returns (address) {
        // Get a random user from the list of lps
        return getRandom(lps, seed);
    }

    function getRandomLPs(uint8 seed, bool withBalance) public view returns (address) {
        // Get a random user from the list of lps
        return withBalance ? getRandomLPsWithBalance(seed) : getRandomLPs(seed);
    }

    function getRandomLPsWithBalance(uint8 seed) public view returns (address) {
        return getRandomLPsWithBalance(seed, 0);
    }

    function getRandomLPsWithBalance(uint256 seed, uint256 minBalance) public view returns (address) {
        // Find a random element on the list with a condition, using Fisher-Yates shuffle
        uint256 len = lps.length;
        uint256[] memory indices = new uint256[](len);

        // 1. Fill the indices array with 0 to n-1
        for (uint256 i; i < len; i++) {
            indices[i] = i;
        }

        // 2. Try up to n different elements without repetition
        for (uint256 j; j < len; j++) {
            // Pick a random index i from the remaining untested part
            uint256 i = j + (seed % (len - j));

            // Swap indices[j] and indices[i] to avoid duplicates
            (indices[j], indices[i]) = (indices[i], indices[j]);

            // Access the element at the shuffled position
            address candidate = lps[indices[j]];

            // Return if it satisfies the condition
            if (originARM.balanceOf(candidate) > minBalance) return candidate;

            // Update the seed to make the next iteration more random
            seed = uint256(keccak256(abi.encodePacked(seed, candidate, i, j)));
        }
        // If no candidate found, return address(0)
        return address(0);
    }

    function getRandomSwapperWithBalance(uint8 seed, uint256 minBalance, IERC20 token)
        public
        view
        returns (address, uint256)
    {
        // Find a random element on the list with a condition, using Fisher-Yates shuffle
        uint256 len = swaps.length;
        uint256[] memory indices = new uint256[](len);

        // 1. Fill the indices array with 0 to n-1
        for (uint256 i; i < len; i++) {
            indices[i] = i;
        }

        // 2. Try up to n different elements without repetition
        for (uint256 j; j < len; j++) {
            // Pick a random index i from the remaining untested part
            uint256 i = j + (uint256(seed) % (len - j));

            // Swap indices[j] and indices[i] to avoid duplicates
            (indices[j], indices[i]) = (indices[i], indices[j]);

            // Access the element at the shuffled position
            address candidate = swaps[indices[j]];
            uint256 balance = token.balanceOf(candidate);

            // Return if it satisfies the condition
            if (balance > minBalance) return (candidate, balance);

            // Update the seed to make the next iteration more random
            seed = uint8(uint256(keccak256(abi.encodePacked(seed, candidate, i, j))));
        }
        return (address(0), 0);
    }

    function getRandomLPsWithRequest(uint256 seed, uint16 seed_id)
        public
        view
        returns (address, uint256, uint256, uint40)
    {
        // Find a random element on the list with a condition, using Fisher-Yates shuffle
        uint256 len = lps.length;
        uint256[] memory indices = new uint256[](len);
        uint256 claimable = originARM.claimable();

        // 1. Fill the indices array with 0 to n-1
        for (uint256 i; i < len; i++) {
            indices[i] = i;
        }

        // 2. Try up to n different elements without repetition
        for (uint256 j; j < len; j++) {
            // Pick a random index i from the remaining untested part
            uint256 i = j + (seed % (len - j));

            // Swap indices[j] and indices[i] to avoid duplicates
            (indices[j], indices[i]) = (indices[i], indices[j]);

            // Access the element at the shuffled position
            address candidate = lps[indices[j]];
            (uint256 id, uint256 asset, uint40 ts) = getRandomClaimableRequestFromUser(candidate, seed_id, claimable);

            // Return if it satisfies the condition
            if (ts > 0) return (candidate, id, asset, ts);

            // Update the seed to make the next iteration more random
            seed = uint256(keccak256(abi.encodePacked(seed, candidate, i, j)));
        }
        // If no candidate found, return 0
        return (address(0), 0, 0, 0);
    }

    function getRandomClaimableRequestFromUser(address user, uint256 seed, uint256 claimable)
        public
        view
        returns (uint256, uint256, uint40)
    {
        // Find a random element on the list with a condition, using Fisher-Yates shuffle
        uint256[] memory requests_ = requests[user];
        uint256 len = requests_.length;
        uint256[] memory indices = new uint256[](len);

        // 1. Fill the indices array with 0 to n-1
        for (uint256 i; i < len; i++) {
            indices[i] = i;
        }

        // 2. Try up to n different elements without repetition
        for (uint256 j; j < len; j++) {
            // Pick a random index i from the remaining untested part
            uint256 i = j + (uint256(seed) % (len - j));

            // Swap indices[j] and indices[i] to avoid duplicates
            (indices[j], indices[i]) = (indices[i], indices[j]);

            // Access the element at the shuffled position
            uint256 id = requests_[indices[j]];
            (,, uint40 ts, uint256 asset, uint256 queued,) = originARM.withdrawalRequests(id);

            // Return if it satisfies the condition
            if (queued <= claimable) return (id, asset, ts);

            // Update the seed to make the next iteration more random
            seed = uint8(uint256(keccak256(abi.encodePacked(seed, asset, i, j))));
        }
        return (0, 0, 0);
    }

    function getRandomOriginRequest(uint256 count, uint256 seed) public returns (uint256[] memory) {
        if (count == 0) return new uint256[](0);

        uint256[] memory list = new uint256[](count);

        for (uint256 i; i < count; i++) {
            uint256 id = uint256(keccak256(abi.encodePacked(seed, i))) % originRequests.length;
            list[i] = originRequests[id];
            // remove id from the list
            if (originRequests.length == 1) {
                delete originRequests;
            } else {
                originRequests[id] = originRequests[originRequests.length - 1];
                originRequests.pop();
            }
        }
        return list;
    }

    function removeRequest(address user, uint256 id) public {
        // Remove the request from the list
        uint256 len = requests[user].length;
        for (uint256 i; i < len; i++) {
            if (requests[user][i] == id) {
                if (len == 1) {
                    delete requests[user];
                } else {
                    requests[user][i] = requests[user][len - 1];
                    requests[user].pop();
                }
                return;
            }
        }
        revert("Request not found");
    }
}
