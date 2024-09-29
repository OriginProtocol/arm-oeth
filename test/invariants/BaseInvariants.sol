// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Invariant_Shared_Test_} from "./shared/Shared.sol";

// Handlers
import {LpHandler} from "./handlers/LpHandler.sol";
import {SwapHandler} from "./handlers/SwapHandler.sol";

abstract contract Invariant_Base_Test_ is Invariant_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////
    address[] public lps; // Users that provide liquidity
    address[] public swaps; // Users that perform swap

    LpHandler public lpHandler;
    SwapHandler public swapHandler;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        super.setUp();
    }

    //////////////////////////////////////////////////////
    /// --- ASSERTIONS
    //////////////////////////////////////////////////////
}
