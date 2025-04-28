// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {TargetFunction} from "test/invariants/OriginARM/TargetFunction.sol";

contract FuzzerFoundry_OriginARM is TargetFunction {
    uint256 private constant NUM_LPS = 4;
    uint256 private constant NUM_SWAPS = 3;
    uint256 private constant INITIAL_AMOUNT = 1_000_000 ether;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        // --- Assigns to Categories ---
        // In this configuration, an user is either a LP or a Swap, but not both.
        require(NUM_LPS + NUM_SWAPS <= users.length, "IBT: NOT_ENOUGH_USERS");

        // LPs
        for (uint256 i; i < NUM_LPS; i++) {
            address user = users[i];
            require(user != address(0), "IBT: INVALID_USER");
            lps.push(user);

            // Give them a lot of WS
            deal(address(ws), user, 100 * INITIAL_AMOUNT);

            // Approve ARM for WS
            vm.prank(user);
            ws.approve(address(originARM), type(uint256).max);
        }

        // Swappers
        for (uint256 i = NUM_LPS; i < NUM_LPS + NUM_SWAPS; i++) {
            address user = users[i];
            require(user != address(0), "IBT: INVALID_USER");
            swaps.push(user);

            // Give them a lot of WS and OS
            deal(address(ws), user, INITIAL_AMOUNT);
            deal(address(os), user, INITIAL_AMOUNT);

            // Approve ARM for WS and OS
            vm.startPrank(user);
            os.approve(address(originARM), type(uint256).max);
            ws.approve(address(originARM), type(uint256).max);
            vm.stopPrank();
        }

        // Distribute a lot of WS to the vault, this will help for redeeming OS
        deal(address(os), address(vault), type(uint128).max);

        // --- Setup ARM ---
        // Set cross price
        vm.prank(governor);
        originARM.setCrossPrice(0.9999 * 1e36);
        // Set prices
        vm.prank(operator);
        originARM.setPrices(MIN_BUY_PRICE, MAX_SELL_PRICE);

        // --- Setup Markets ---
        markets = new address[](2);
        markets[0] = address(market);
        markets[1] = address(siloMarket);
        vm.prank(governor);
        originARM.addMarkets(markets);

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
    function invariant_B() public {}

    function afterInvariant() public {
        handler_afterInvariants();
    }
}
