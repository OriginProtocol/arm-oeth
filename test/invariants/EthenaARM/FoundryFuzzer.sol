// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Properties} from "./Properties.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";

/// @title FuzzerFoundry
/// @notice Concrete fuzzing contract implementing Foundry's invariant testing framework.
/// @dev    This contract configures and executes property-based testing:
///         - Inherits from Properties to access handler functions and properties
///         - Configures fuzzer targeting (contracts, selectors, senders)
///         - Implements invariant test functions that call property validators
///         - Each invariant function represents a critical system property to maintain
///         - Fuzzer will call targeted handlers randomly and check invariants after each call
contract FuzzerFoundry_EthenaARM is Properties, StdInvariant, StdAssertions {
    bool public constant override isLabelAvailable = true;
    bool public constant override isAssumeAvailable = true;
    bool public constant override isConsoleAvailable = true;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        // --- Setup Fuzzer target ---
        // Setup target
        targetContract(address(this));

        // Add selectors
        bytes4[] memory selectors = new bytes4[](22);
        // --- sUSDe ---
        selectors[0] = this.targetSUSDeDeposit.selector;
        selectors[1] = this.targetSUSDeCooldownShares.selector;
        selectors[2] = this.targetSUSDeUnstake.selector;
        selectors[3] = this.targetSUSDeTransferInRewards.selector;
        // --- Morpho ---
        selectors[4] = this.targetMorphoDeposit.selector;
        selectors[5] = this.targetMorphoWithdraw.selector;
        selectors[6] = this.targetMorphoTransferInRewards.selector;
        selectors[7] = this.targetMorphoSetUtilizationRate.selector;
        // --- ARM ---
        selectors[8] = this.targetARMDeposit.selector;
        selectors[9] = this.targetARMRequestRedeem.selector;
        selectors[10] = this.targetARMClaimRedeem.selector;
        selectors[11] = this.targetARMSetARMBuffer.selector;
        selectors[12] = this.targetARMSetActiveMarket.selector;
        selectors[13] = this.targetARMAllocate.selector;
        selectors[14] = this.targetARMSetPrices.selector;
        selectors[15] = this.targetARMSetCrossPrice.selector;
        selectors[16] = this.targetARMSwapExactTokensForTokens.selector;
        selectors[17] = this.targetARMSwapTokensForExactTokens.selector;
        selectors[18] = this.targetARMCollectFees.selector;
        selectors[19] = this.targetARMSetFees.selector;
        selectors[20] = this.targetARMRequestBaseWithdrawal.selector;
        selectors[21] = this.targetARMClaimBaseWithdrawals.selector;
        // Target selectors
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    //////////////////////////////////////////////////////
    /// --- INVARIANTS
    //////////////////////////////////////////////////////
    function invariantA() public view {
        assertTrue(propertyA());
        assertTrue(propertyB());
    }
}
