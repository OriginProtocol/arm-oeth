// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Invariant_Shared_Test_} from "./shared/Shared.sol";

// Handlers
import {LpHandler} from "./handlers/LpHandler.sol";
import {LLMHandler} from "./handlers/LLMHandler.sol";
import {SwapHandler} from "./handlers/SwapHandler.sol";
import {OwnerHandler} from "./handlers/OwnerHandler.sol";

abstract contract Invariant_Base_Test_ is Invariant_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////
    address[] public lps; // Users that provide liquidity
    address[] public swaps; // Users that perform swap

    LpHandler public lpHandler;
    LLMHandler public llmHandler;
    SwapHandler public swapHandler;
    OwnerHandler public ownerHandler;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        super.setUp();
    }

    //////////////////////////////////////////////////////
    /// --- ASSERTIONS
    //////////////////////////////////////////////////////
    function assert_invariant_A() public pure {
        assertTrue(true);
    }

    function assert_invariant_B() public pure {
        assertFalse(false);
    }
}
