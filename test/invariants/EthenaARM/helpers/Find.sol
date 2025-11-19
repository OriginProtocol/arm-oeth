// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AbstractARM} from "contracts/AbstractARM.sol";

/// @notice Library used to find specific data in storage for testing purposes.
///         Most of the time to find a specific user/request that meets certain criteria.
library Find {
    struct GetUserRequestWithAmountStruct {
        address arm;
        uint248 randomAddressIndex;
        uint248 randomArrayIndex;
        address[] users;
        uint256 targetAmount;
    }

    function getUserRequestWithAmount(
        GetUserRequestWithAmountStruct memory $,
        mapping(address => uint256[]) storage pendingRequests
    ) internal returns (address user, uint256 requestId, uint40 claimTimestamp) {
        uint256 usersLen = $.users.length;
        for (uint256 i; i < usersLen; i++) {
            // Take a random user
            address _user = $.users[($.randomAddressIndex + i) % usersLen];
            // Find a request that can be claimed
            for (uint256 j; j < pendingRequests[_user].length; j++) {
                // Take a random request from that user
                uint256 _requestId = pendingRequests[_user][($.randomArrayIndex + j) % pendingRequests[_user].length];
                // Check request data
                (,, uint40 _claimTimestamp, uint128 _amount,) = AbstractARM($.arm).withdrawalRequests(_requestId);
                // Check if this is claimable
                if (_amount <= $.targetAmount) {
                    (user, requestId, claimTimestamp) = (_user, _requestId, _claimTimestamp);
                    // Remove pendingRequests
                    pendingRequests[_user][($.randomArrayIndex + j) % pendingRequests[_user].length] =
                        pendingRequests[_user][pendingRequests[_user].length - 1];
                    pendingRequests[_user].pop();
                    break;
                }
            }
        }
    }
}
