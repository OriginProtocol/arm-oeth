// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "contracts/Interfaces.sol";

contract MockVault {
    IERC20 public token;
    uint256 public requestCount;
    mapping(uint256 => uint256) public requestIds;
    mapping(uint256 => bool) public requestStatus;

    constructor(IERC20 _token) {
        token = _token;
    }

    function requestWithdrawal(uint256 _amount) external returns (uint256) {
        // Increase the request count
        requestCount++;
        // Store the request ID and amount
        requestIds[requestCount] = _amount;
        // Return the request ID
        return requestCount;
    }

    function claimWithdrawals(uint256[] calldata _requestIds)
        external
        returns (uint256[] memory amounts, uint256 totalAmount)
    {
        // Cache length of the request IDs
        uint256 length = _requestIds.length;
        // Initialize the amounts array
        amounts = new uint256[](length);

        // Loop through the request IDs and populate the amounts array
        for (uint256 i; i < length; i++) {
            // Cache the request ID
            uint256 requestId = _requestIds[i];

            // Ensure the request ID is valid and not already claimed
            require(requestStatus[requestId] == false, "Request already claimed");
            // Set the request status to claimed
            requestStatus[requestId] = true;

            // Store the amount and add it to the total amount
            amounts[i] = requestIds[requestId];
            totalAmount += requestIds[requestId];
        }

        // Transfer the total amount to the caller
        token.transfer(msg.sender, totalAmount);

        return (amounts, totalAmount);
    }
}
