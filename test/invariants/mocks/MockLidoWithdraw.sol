// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {Vm} from "forge-std/Vm.sol";

// Solmate
import {ERC20} from "@solmate/tokens/ERC20.sol";

contract MockLidoWithdraw {
    //////////////////////////////////////////////////////
    /// --- CONSTANTS && IMMUTABLES
    //////////////////////////////////////////////////////
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    //////////////////////////////////////////////////////
    /// --- STRUCTS & ENUMS
    //////////////////////////////////////////////////////
    struct Request {
        bool claimed;
        address owner;
        uint256 amount;
    }

    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////
    ERC20 public steth;

    uint256 public counter;

    // Request Id -> Request struct
    mapping(uint256 => Request) public requests;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////
    constructor(address _steth) {
        steth = ERC20(_steth);
    }

    //////////////////////////////////////////////////////
    /// --- FUNCTIONS
    //////////////////////////////////////////////////////
    function requestWithdrawals(uint256[] memory amounts, address owner) external returns (uint256[] memory) {
        uint256 len = amounts.length;
        uint256[] memory userRequests = new uint256[](len);

        for (uint256 i; i < len; i++) {
            require(amounts[i] <= 1_000 ether, "Mock LW: Withdraw amount too big");

            // Due to rounding error issue, we need to check balance before and after.
            uint256 balBefore = steth.balanceOf(address(this));
            steth.transferFrom(msg.sender, address(this), amounts[i]);
            uint256 amount = steth.balanceOf(address(this)) - balBefore;

            // Update request mapping
            requests[counter] = Request({claimed: false, owner: owner, amount: amount});
            userRequests[i] = counter;
            // Increase request count
            counter++;
        }

        return userRequests;
    }

    function claimWithdrawals(uint256[] memory requestId, uint256[] memory) external {
        uint256 sum;
        uint256 len = requestId.length;
        for (uint256 i; i < len; i++) {
            // Cache id
            uint256 id = requestId[i];

            // Ensure msg.sender is the owner
            require(requests[id].owner == msg.sender, "Mock LW: Not owner");
            requests[id].claimed = true;
            sum += requests[id].amount;
        }

        // Send sum of eth
        vm.deal(address(msg.sender), address(msg.sender).balance + sum);
    }

    function getLastCheckpointIndex() external returns (uint256) {}

    function findCheckpointHints(uint256[] memory, uint256, uint256) external returns (uint256[] memory) {}
}
