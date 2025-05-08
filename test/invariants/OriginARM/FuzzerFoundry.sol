// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {TargetFunction} from "test/invariants/OriginARM/TargetFunction.sol";

contract FuzzerFoundry_OriginARM is TargetFunction {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        // --- Setup Fuzzer target ---
        // Setup target
        targetContract(address(this));

        // Add selectors
        bytes4[] memory selectors = new bytes4[](15);
        selectors[0] = this.handler_deposit.selector;
        selectors[1] = this.handler_requestRedeem.selector;
        selectors[2] = this.handler_claimRedeem.selector;
        selectors[3] = this.handler_setARMBuffer.selector;
        selectors[4] = this.handler_setActiveMarket.selector;
        selectors[5] = this.handler_allocate.selector;
        selectors[6] = this.handler_setPrices.selector;
        selectors[7] = this.handler_setCrossPrice.selector;
        selectors[8] = this.handler_swapExactTokensForTokens.selector;
        selectors[9] = this.handler_swapTokensForExactTokens.selector;
        selectors[10] = this.handler_collectFees.selector;
        selectors[11] = this.handler_setFee.selector;
        selectors[12] = this.handler_requestOriginWithdrawal.selector;
        selectors[13] = this.handler_claimOriginWithdrawals.selector;
        selectors[14] = this.handler_donateToARM.selector;

        // Target selectors
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    //////////////////////////////////////////////////////
    /// --- INVARIANTS
    //////////////////////////////////////////////////////
    function invariant_swap() public view {
        assertTrue(property_swap_A(), "INVARIANT A");
        assertTrue(property_swap_B(), "INVARIANT B");
    }

    function invariant_lp() public view {
        assertTrue(property_lp_A(), "INVARIANT A");
        assertTrue(property_lp_B(), "INVARIANT B");
        assertTrue(property_lp_C(), "INVARIANT C");
        assertTrue(property_lp_G(), "INVARIANT G");
        assertTrue(property_lp_H(), "INVARIANT H");
        assertTrue(property_lp_I(), "INVARIANT I");
        assertTrue(property_lp_J(), "INVARIANT J");
        assertTrue(property_lp_K(), "INVARIANT K");
        assertTrue(property_lp_L(), "INVARIANT L");
    }

    function afterInvariant() public {
        handler_afterInvariants();
        assertLpsAreUpOnly(originARM.minSharesToRedeem());
    }
}
