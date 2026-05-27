// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {Vm} from "forge-std/Vm.sol";

// Solmate
import {ERC20} from "@solmate/tokens/ERC20.sol";

/// @notice Test double for Lido's `WithdrawalQueueERC721`. Implements the subset of
///         `IStETHWithdrawal` exercised by `AbstractLidoAssetAdapter` and exposes
///         `mock_*` setters so unit tests can drive un-finalized / claimed / re-owned
///         requests through the adapter's edge-case branches.
contract MockLidoWithdraw {
    //////////////////////////////////////////////////////
    /// --- CONSTANTS && IMMUTABLES
    //////////////////////////////////////////////////////
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    //////////////////////////////////////////////////////
    /// --- STRUCTS
    //////////////////////////////////////////////////////
    struct Request {
        address owner;
        uint256 amount;
        bool claimed;
        bool finalized;
    }

    // Field order must match IStETHWithdrawal.WithdrawalRequestStatus exactly.
    struct WithdrawalRequestStatus {
        uint256 amountOfStETH;
        uint256 amountOfShares;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }

    //////////////////////////////////////////////////////
    /// --- STATE
    //////////////////////////////////////////////////////
    ERC20 public steth;
    uint256 public counter;
    uint256 public lastCheckpointIndex;
    mapping(uint256 => Request) public requests;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////
    constructor(address _steth) {
        steth = ERC20(_steth);
    }

    //////////////////////////////////////////////////////
    /// --- IStETHWithdrawal (subset used by the adapter)
    //////////////////////////////////////////////////////
    function requestWithdrawals(uint256[] calldata amounts, address owner) external returns (uint256[] memory ids) {
        uint256 len = amounts.length;
        ids = new uint256[](len);

        for (uint256 i; i < len; ++i) {
            require(amounts[i] <= 1_000 ether, "Mock LW: Withdraw amount too big");

            // stETH transfers can lose 1 wei to rounding; measure the actual delta.
            uint256 balBefore = steth.balanceOf(address(this));
            steth.transferFrom(msg.sender, address(this), amounts[i]);
            uint256 amount = steth.balanceOf(address(this)) - balBefore;

            requests[counter] = Request({owner: owner, amount: amount, claimed: false, finalized: true});
            ids[i] = counter;
            counter++;
        }
    }

    function claimWithdrawals(uint256[] calldata requestIds, uint256[] calldata) external {
        uint256 sum;
        uint256 len = requestIds.length;
        for (uint256 i; i < len; ++i) {
            uint256 id = requestIds[i];
            Request storage r = requests[id];
            require(r.owner == msg.sender, "Mock LW: Not owner");
            require(!r.claimed, "Mock LW: Already claimed");
            require(r.finalized, "Mock LW: Not finalized");

            r.claimed = true;
            sum += r.amount;
        }

        // Fund the caller (the adapter) with ETH; it will wrap to WETH itself.
        vm.deal(msg.sender, msg.sender.balance + sum);
    }

    function getWithdrawalStatus(uint256[] calldata requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses)
    {
        uint256 len = requestIds.length;
        statuses = new WithdrawalRequestStatus[](len);
        for (uint256 i; i < len; ++i) {
            Request memory r = requests[requestIds[i]];
            statuses[i] = WithdrawalRequestStatus({
                amountOfStETH: r.amount,
                amountOfShares: r.amount,
                owner: r.owner,
                timestamp: block.timestamp,
                isFinalized: r.finalized,
                isClaimed: r.claimed
            });
        }
    }

    function getLastCheckpointIndex() external view returns (uint256) {
        return lastCheckpointIndex;
    }

    function findCheckpointHints(uint256[] calldata requestIds, uint256, uint256)
        external
        pure
        returns (uint256[] memory hints)
    {
        // Hints array must match requestIds length; values are unused by this mock.
        hints = new uint256[](requestIds.length);
    }

    //////////////////////////////////////////////////////
    /// --- Test knobs
    //////////////////////////////////////////////////////
    function mock_setFinalized(uint256 id, bool value) external {
        requests[id].finalized = value;
    }

    function mock_setClaimed(uint256 id, bool value) external {
        requests[id].claimed = value;
    }

    function mock_setOwner(uint256 id, address newOwner) external {
        requests[id].owner = newOwner;
    }

    function mock_setLastCheckpointIndex(uint256 idx) external {
        lastCheckpointIndex = idx;
    }

    receive() external payable {}
}
