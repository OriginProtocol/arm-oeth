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
contract FuzzerFoundry_LidoARM is Properties {
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

    function invariant_lp() public view {
        require(property_lp_A(), "LP_A: totalSupply == 0");
        require(property_lp_B(), "LP_B: totalSupply != sum of balances");
        require(property_lp_C(), "LP_C: previewRedeem != totalAssets");
        require(property_lp_D(), "LP_D: reservedWithdrawLiquidity mismatch");
        require(property_lp_E(), "LP_E: queued < claimed");
        require(property_lp_F(), "LP_F: queuedShares != ghost");
        require(property_lp_G(), "LP_G: claimedShares != ghost");
        require(property_lp_H(), "LP_H: escrowed shares mismatch");
        require(property_lp_I(), "LP_I: feeCollector balance mismatch");
        require(property_lp_noLoss(), "LP_LOSS: user lost value");
    }

    function invariant_withdrawalIndex() public view {
        require(property_wi_A(), "WI_A: nextWithdrawalIndex != ghost");
    }

    function invariant_liquidity() public view {
        require(property_llm_A(), "LLM_A: ARM holds native ETH");
    }

    function invariant_fees() public view {
        require(property_fee_A(), "FEE_A: fee accounting mismatch");
        require(property_fee_B(), "FEE_B: fees exceed upper bound");
    }

    function invariant_balances() public view {
        require(property_bal_weth(), "BAL_WETH: WETH balance mismatch");
        require(property_bal_steth(), "BAL_STETH: stETH balance mismatch");
        require(property_bal_wsteth(), "BAL_WSTETH: wstETH balance mismatch");
    }

    /// @notice Optimization: fuzzer maximizes the worst-case LP rounding loss.
    function invariant_optimize_maxLpLoss() public view returns (int256) {
        return maxLpLoss();
    }

    /// @notice Optimization: fuzzer maximizes WETH balance drift from market rounding.
    function invariant_optimize_maxWethDrift() public view returns (int256) {
        return maxWethBalanceDrift();
    }

    /// @notice Optimization: fuzzer maximizes share price drop in a single call.
    function invariant_optimize_maxSharePriceDrop() public view returns (int256) {
        return sharePriceDrop();
    }
}
