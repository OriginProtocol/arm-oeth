// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Setup} from "./Setup.sol";
import {Logger} from "test/invariants/OriginARM/Logger.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

abstract contract Helpers is Setup, Logger {
    uint256[] private _emptyUint256;
    address[] private _emptyAddress;
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

    function getRandomSwapperWithBalance(uint8 seed, uint256 minBalance, IERC20 token)
        public
        view
        returns (address, uint256)
    {
        // Get a random user from the list of swaps with a balance
        uint256 len = swaps.length;
        for (uint256 i; i < len; i++) {
            address user_ = swaps[(seed + i) % len];
            uint256 balance = token.balanceOf(user_);
            if (balance > minBalance) {
                return (user_, balance);
            }
        }
        return (address(0), 0);
    }

    function getRandomLPsWithRequest(uint8 seed, uint16 seed_id) public returns (address, uint256, uint256, uint40) {
        // Get a random user from the list of lps with a request
        uint256 len = lps.length;

        // If no liquidity available, no need to look for a user with a request
        uint256 claimable = originARM.claimable();
        if (claimable == 0) return (address(0), 0, 0, 0);

        // Find a user with a request
        for (uint256 i; i < len; i++) {
            address user_ = lps[(seed + i) % len];
            // Check if the user has a request
            if (requests[user_].length > 0) {
                // Cache the requests for the user
                _emptyUint256 = requests[user_];

                // This is another way to get a random value from the list, as it will not take the next one
                // but a random one from the list at every iteration. In comparison to picking a random user
                // on the first lps list where the next user is always the next one (not a random one).
                while (_emptyUint256.length > 0) {
                    uint256 id = _emptyUint256[seed_id % _emptyUint256.length];
                    // Check if the request is claimable
                    (,, uint40 ts, uint256 asset, uint256 queued) = originARM.withdrawalRequests(id);

                    // If claimable, we find the user and the id!
                    if (queued <= claimable) {
                        return (user_, id, asset, ts);
                    }
                    // Otherwise remove the id from the temporary list
                    else {
                        if (_emptyUint256.length == 1) {
                            _emptyUint256.pop();
                        } else {
                            _emptyUint256[seed_id % _emptyUint256.length] = _emptyUint256[_emptyUint256.length - 1];
                            _emptyUint256.pop();
                        }
                    }
                }
            }
        }
        return (address(0), 0, 0, 0);
    }

    function getRandomOriginRequest(uint256 count, uint256 seed) public returns (uint256[] memory) {
        if (count == 0) return new uint256[](0);

        uint256[] memory list = new uint256[](count);

        for (uint256 i; i < count; i++) {
            list[i] = originRequests[uint256(keccak256(abi.encodePacked(seed, i))) % originRequests.length];
            // remove id from the list
            if (originRequests.length == 1) {
                delete originRequests;
            } else {
                originRequests[uint256(keccak256(abi.encodePacked(seed, i))) % originRequests.length] =
                    originRequests[originRequests.length - 1];
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

    function roundToOneDecimal(uint256 amount) internal pure returns (uint256) {
        uint256 oneDecimal = 1e16;

        return (amount / oneDecimal) * oneDecimal;
    }

    function uintArrayToString(uint256[] memory _array) public pure returns (string memory) {
        bytes memory result;

        for (uint256 i = 0; i < _array.length; i++) {
            result = abi.encodePacked(result, vm.toString(_array[i]));
            if (i < _array.length - 1) {
                result = abi.encodePacked(result, ", ");
            }
        }

        return string(result);
    }
}
