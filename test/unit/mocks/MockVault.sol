// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "contracts/Interfaces.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

contract MockVault {
    IERC20 public oToken;
    IERC20 public baseToken;
    uint256 public requestCount;
    mapping(uint256 => uint256) public requestIds;
    mapping(uint256 => bool) public requestStatus;

    constructor(IERC20 _oToken, IERC20 _baseToken) {
        oToken = _oToken;
        baseToken = _baseToken;
    }

    function requestWithdrawal(uint256 _amount) external returns (uint256, uint256) {
        MockERC20(address(oToken)).burn(msg.sender, _amount);
        // Increase the request count
        requestCount++;
        // Store the request ID and amount
        requestIds[requestCount] = _amount;
        // Return the request ID
        return (requestCount, 0);
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
        baseToken.transfer(msg.sender, totalAmount);

        return (amounts, totalAmount);
    }
}
