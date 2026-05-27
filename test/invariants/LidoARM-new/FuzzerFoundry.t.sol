// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Properties} from "./Properties.t.sol";

/// @title FuzzerFoundry_LidoARM
/// @notice Concrete fuzzing contract implementing Foundry's invariant testing framework.
/// @dev    This contract configures and executes property-based testing:
///         - Inherits from Properties to access handler functions and properties
///         - Configures fuzzer targeting (contracts, selectors, senders)
///         - Implements invariant test functions that call property validators
///         - Each invariant function represents a critical system property to maintain
///         - Fuzzer will call targeted handlers randomly and check invariants after each call
contract FuzzerFoundry_LidoARM_New is Properties {
    constructor() {
        consoleLogs = true;
        foundryFuzzer = true;
    }

    function setUp() public virtual override {
        // --- Common setup ---
        super.setUp();

        // --- Setup Fuzzer target ---
        // Setup target
        targetContract(address(this));

        // Add selectors
        bytes4[] memory selectors = new bytes4[](21);
        uint256 i;

        // --- Swaps ---
        selectors[i++] = this.targetSwapExactTokensForTokens.selector;
        selectors[i++] = this.targetSwapTokensForExactTokens.selector;

        // --- LP lifecycle ---
        selectors[i++] = this.targetDeposit.selector;
        selectors[i++] = this.targetRequestRedeem.selector;
        selectors[i++] = this.targetClaimRedeem.selector;
        selectors[i++] = this.targetTransferShares.selector;

        // --- Base asset redemptions ---
        selectors[i++] = this.targetRequestBaseWithdrawal.selector;
        selectors[i++] = this.targetClaimBaseWithdrawals.selector;

        // --- Liquidity management ---
        selectors[i++] = this.targetAllocate.selector;
        selectors[i++] = this.targetSetActiveMarket.selector;
        selectors[i++] = this.targetSetARMBuffer.selector;

        // --- Prices & fees ---
        selectors[i++] = this.targetSetPrices.selector;
        selectors[i++] = this.targetSetCrossPrice.selector;
        selectors[i++] = this.targetSetFee.selector;
        selectors[i++] = this.targetCollectFees.selector;

        // --- Lido (external protocol) ---
        selectors[i++] = this.targetRebase.selector;
        selectors[i++] = this.targetDonate.selector;

        // --- ERC4626 markets (external protocol) ---
        selectors[i++] = this.targetSetUtilizationRate.selector;
        selectors[i++] = this.targetMarketDeposit.selector;
        selectors[i++] = this.targetMarketWithdraw.selector;
        selectors[i++] = this.targetMarketTransferRewards.selector;

        // Target selectors
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    function invariantSwap() public view {
        // Example invariant test function
    }
}
