// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {console} from "forge-std/console.sol";

// Handlers
import {BaseHandler} from "./BaseHandler.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {LidoARM} from "contracts/LidoARM.sol";

/// @notice LidoLiquidityManager Handler contract
/// @dev This contract is used to handle all functionnalities that are related to the Lido Liquidity Manager.
contract LLMHandler is BaseHandler {
    ////////////////////////////////////////////////////
    /// --- CONSTANTS && IMMUTABLES
    ////////////////////////////////////////////////////
    IERC20 public immutable steth;
    LidoARM public immutable arm;
    address public immutable owner;
    uint256 public constant MAX_AMOUNT = 1_000 ether;

    ////////////////////////////////////////////////////
    /// --- VARIABLES
    ////////////////////////////////////////////////////
    uint256[] public requestIds;

    ////////////////////////////////////////////////////
    /// --- VARIABLES FOR INVARIANT ASSERTIONS
    ////////////////////////////////////////////////////
    uint256 public sum_of_outstanding_ether;
    uint256 public sum_of_requested_ether;
    uint256 public sum_of_redeemed_ether;

    ////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ////////////////////////////////////////////////////
    constructor(address _arm, address _steth) {
        arm = LidoARM(payable(_arm));
        owner = arm.owner();
        steth = IERC20(_steth);
    }

    ////////////////////////////////////////////////////
    /// --- ACTIONS
    ////////////////////////////////////////////////////
    function requestStETHWithdrawalForETH(uint256 _seed) external {
        numberOfCalls["llmHandler.requestStETHWithdraw"]++;

        // Select a random amount
        uint256 totalAmount = _bound(_seed, 0, min(MAX_AMOUNT * 3, steth.balanceOf(address(arm))));

        // We can only request only 1k amount at a time
        uint256 batch = (totalAmount / MAX_AMOUNT) + 1;
        uint256[] memory amounts = new uint256[](batch);
        uint256 totalAmount_ = totalAmount;
        for (uint256 i = 0; i < batch; i++) {
            if (totalAmount_ >= MAX_AMOUNT) {
                amounts[i] = MAX_AMOUNT;
                totalAmount_ -= MAX_AMOUNT;
            } else {
                amounts[i] = totalAmount_;
                totalAmount_ = 0;
            }
        }
        require(totalAmount_ == 0, "LLMHandler: Invalid total amount");

        console.log("LLMHandler.requestStETHWithdrawalForETH(%18e)", totalAmount);

        // Prank Owner
        vm.startPrank(owner);

        // Request stETH withdrawal for ETH
        uint256[] memory requestId = arm.requestStETHWithdrawalForETH(amounts);

        // Stop Prank
        vm.stopPrank();

        // Update state
        for (uint256 i = 0; i < requestId.length; i++) {
            requestIds.push(requestId[i]);
        }

        // Update sum_of_outstanding_ether
        sum_of_outstanding_ether += totalAmount;

        sum_of_requested_ether += totalAmount;
    }

    function claimStETHWithdrawalForWETH(uint256 _seed) external {
        numberOfCalls["llmHandler.claimStETHWithdraw"]++;

        // Select multiple requestIds
        uint256 len = requestIds.length;
        uint256 requestCount = _bound(_seed, 0, len);
        uint256[] memory requestIds_ = new uint256[](requestCount);
        for (uint256 i = 0; i < requestCount; i++) {
            requestIds_[i] = requestIds[i];
        }

        // Remove requestIds from list
        uint256[] memory newRequestIds = new uint256[](len - requestCount);
        for (uint256 i = requestCount; i < len; i++) {
            newRequestIds[i - requestCount] = requestIds[i];
        }
        requestIds = newRequestIds;

        // As `claimStETHWithdrawalForWETH` doesn't send back the amount, we need to calculate it
        uint256 outstandingBefore = arm.outstandingEther();

        // Prank Owner
        vm.startPrank(owner);

        // Claim stETH withdrawal for WETH
        arm.claimStETHWithdrawalForWETH(requestIds_);

        // Stop Prank
        vm.stopPrank();

        uint256 outstandingAfter = arm.outstandingEther();
        uint256 diff = outstandingBefore - outstandingAfter;

        console.log("LLMHandler.claimStETHWithdrawalForWETH(%18e)", diff);

        // Update sum_of_outstanding_ether
        sum_of_outstanding_ether -= diff;

        sum_of_redeemed_ether += diff;
    }
}
