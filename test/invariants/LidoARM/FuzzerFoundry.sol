// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {TargetFunction} from "test/invariants/LidoARM/TargetFunction.sol";

contract FuzzerFoundry_LidoARM is TargetFunction {
    uint256 private constant NUM_LPS = 4;
    uint256 private constant NUM_SWAPS = 3;
    uint256 private constant MAX_WETH_PER_USERS = 1_000_000 ether;
    uint256 private constant MAX_STETH_PER_USERS = 1_000_000 ether;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        // --- Create Users ---
        // In this configuration, an user is either a LP or a Swap, but not both.
        require(NUM_LPS + NUM_SWAPS <= users.length, "IBT: NOT_ENOUGH_USERS");
        for (uint256 i; i < NUM_LPS; i++) {
            address user = users[i];
            require(user != address(0), "IBT: INVALID_USER");
            lps.push(user);

            // Give them a lot of wETH
            deal(address(weth), user, MAX_WETH_PER_USERS);

            // Approve ARM for wETH
            vm.prank(user);
            weth.approve(address(lidoARM), type(uint256).max);
        }
        for (uint256 i = NUM_LPS; i < NUM_LPS + NUM_SWAPS; i++) {
            address user = users[i];
            require(user != address(0), "IBT: INVALID_USER");
            swaps.push(user);

            // Give them a lot of wETH and stETH
            deal(address(weth), user, MAX_WETH_PER_USERS);
            deal(address(steth), user, MAX_STETH_PER_USERS);

            // Approve ARM for stETH and wETH
            vm.startPrank(user);
            steth.approve(address(lidoARM), type(uint256).max);
            weth.approve(address(lidoARM), type(uint256).max);
            vm.stopPrank();
        }

        // --- Setup ARM ---
        // Max caps on the total asset that can be deposited
        vm.prank(capManager.owner());
        capManager.setTotalAssetsCap(type(uint248).max);

        // Set prices, start with almost 1:1
        vm.prank(lidoARM.owner());
        lidoARM.setPrices(1e36 - 1, 1e36);

        // --- Setup Fuzzer target ---
        // Setup target
        targetContract(address(this));

        // Add selectors
        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = this.handler_swapExactTokensForTokens.selector;
        selectors[1] = this.handler_swapTokensForExactTokens.selector;
        selectors[2] = this.handler_deposit.selector;
        selectors[3] = this.handler_requestRedeem.selector;
        selectors[4] = this.handler_claimRedeem.selector;
        selectors[5] = this.handler_requestLidoWithdrawals.selector;
        selectors[6] = this.handler_claimLidoWithdrawals.selector;
        selectors[7] = this.handler_setPrices.selector;
        selectors[8] = this.handler_setCrossPrice.selector;
        selectors[9] = this.handler_setFee.selector;
        selectors[10] = this.handler_collectFees.selector;
        selectors[11] = this.handler_donate.selector;

        // Target selectors
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    //////////////////////////////////////////////////////
    /// --- INVARIANTS
    //////////////////////////////////////////////////////
    function invariant_swap_A() public view {
        assertTrue(property_swap_A());
    }

    function invariant_swap_B() public view {
        assertTrue(property_swap_B());
    }

    function invariant_swap_C_D() public view {
        assertTrue(property_swap_C());
        assertTrue(property_swap_D());
    }

    function invariant_lp_A() public view {
        assertTrue(property_lp_A());
    }

    function invariant_lp_B() public view {
        assertTrue(property_lp_B());
    }

    function invariant_lp_C() public view {
        assertTrue(property_lp_C());
    }

    function invariant_lp_D_E() public view {
        assertTrue(property_lp_D());
        assertTrue(property_lp_E());
    }

    function invariant_lp_F() public view {
        assertTrue(property_lp_F());
    }

    function invariant_lp_G() public view {
        assertTrue(property_lp_G());
    }

    function invariant_lp_H() public view {
        assertTrue(property_lp_H());
    }

    function invariant_lp_I() public view {
        assertTrue(property_lp_I());
    }

    function invariant_lp_J() public view {
        assertTrue(property_lp_invariant_J());
    }

    function invariant_lp_K() public view {
        assertTrue(property_lp_invariant_K());
    }

    function invariant_lp_M() public view {
        assertTrue(property_lp_invariant_M());
    }

    function invariant_llm_A() public view {
        assertTrue(property_llm_A());
    }

    function afterInvariant() public {
        finalizeLidoClaims();
        sweepAllStETH();
        finalizeUserClaims();
        assertTrue(ensureSharesAreUpOnly(MAX_WETH_PER_USERS), "Shares are not up only");
    }
}
