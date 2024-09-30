// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {Vm} from "forge-std/Vm.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

abstract contract BaseHandler is StdUtils, StdCheats {
    //////////////////////////////////////////////////////
    /// --- CONSTANTS && IMMUTABLES
    //////////////////////////////////////////////////////
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant WEIGHTS_RANGE = 10_000;

    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////
    uint256 public numCalls;
    uint256 public totalWeight;

    bytes4[] public selectors;

    mapping(address => string) public names;
    mapping(bytes4 => uint256) public weights;
    mapping(bytes32 => uint256) public numberOfCalls;

    constructor() {
        // Default names
        names[makeAddr("Alice")] = "Alice";
        names[makeAddr("Bob")] = "Bob";
        names[makeAddr("Charlie")] = "Charlie";
        names[makeAddr("Dave")] = "Dave";
        names[makeAddr("Eve")] = "Eve";
        names[makeAddr("Frank")] = "Frank";
        names[makeAddr("George")] = "George";
        names[makeAddr("Harry")] = "Harry";
    }

    //////////////////////////////////////////////////////
    /// --- FUNCTIONS
    //////////////////////////////////////////////////////
    function setSelectorWeight(bytes4 funcSelector, uint256 weight_) external {
        // Set Selector weight
        weights[funcSelector] = weight_;

        // Add selector to the selector list
        selectors.push(funcSelector);

        // Increase totalWeight
        totalWeight += weight_;
    }

    function entryPoint(uint256 seed_) external {
        require(totalWeight == WEIGHTS_RANGE, "HB:INVALID_WEIGHTS");

        numCalls++;

        uint256 range_;

        uint256 value_ = uint256(keccak256(abi.encodePacked(seed_, numCalls))) % WEIGHTS_RANGE + 1; // 1 - 100

        for (uint256 i = 0; i < selectors.length; i++) {
            uint256 weight_ = weights[selectors[i]];

            range_ += weight_;
            if (value_ <= range_ && weight_ != 0) {
                (bool success,) = address(this).call(abi.encodeWithSelector(selectors[i], seed_));

                // TODO: Parse error from low-level call and revert with it
                require(success, "HB:CALL_FAILED");
                break;
            }
        }
    }

    //////////////////////////////////////////////////////
    /// --- HELPERS
    //////////////////////////////////////////////////////
    function _randomize(uint256 seed, string memory salt) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(seed, salt)));
    }
}
