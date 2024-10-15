// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {console} from "forge-std/console.sol";

// Test imports
import {Invariant_Shared_Test_} from "./shared/Shared.sol";

// Handlers
import {LpHandler} from "./handlers/LpHandler.sol";
import {LLMHandler} from "./handlers/LLMHandler.sol";
import {SwapHandler} from "./handlers/SwapHandler.sol";
import {OwnerHandler} from "./handlers/OwnerHandler.sol";
import {DonationHandler} from "./handlers/DonationHandler.sol";

// Mocks
import {MockSTETH} from "./mocks/MockSTETH.sol";

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
    DonationHandler public donationHandler;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        super.setUp();
    }

    //////////////////////////////////////////////////////
    /// --- INVARIANTS
    //////////////////////////////////////////////////////
    /*
     * Swap functionnalities (swap)
        * Invariant A: weth balance == ∑deposit + ∑wethIn + ∑wethRedeem + ∑wethDonated - ∑withdraw - ∑wethOut - ∑feesCollected
        * Invariant B: steth balance >= ∑stethIn + ∑stethDonated - ∑stethOut - ∑stethRedeem
    
     * Liquidity provider functionnalities (lp)
        * Shares:
            * Invariant A: ∑shares > 0 due to initial deposit
            * Invariant B: totalShares == ∑userShares + deadShares
            * Invariant C: previewRedeem(∑shares) == totalAssets
            * Invariant D: previewRedeem(shares) == (, uint256 assets) = previewRedeem(shares) Not really invariant, but tested on handler
            * Invariant E: previewDeposit(amount) == uint256 shares = previewDeposit(amount) Not really invariant, but tested on handler

        * Withdraw Queue:
            * Invariant F: nextWithdrawalIndex == requestRedeem call count
            * Invariant G: withdrawsQueued == ∑requestRedeem.amount
            * Invariant H: withdrawsQueued > withdrawsClaimed
            * Invariant I: withdrawsQueued == ∑request.assets
            * Invariant J: withdrawsClaimed == ∑claimRedeem.amount
            * Invariant K: ∀ requestId, request.queued >= request.assets

        * Fees:
            * Invariant M: ∑feesCollected == feeCollector.balance

     * Lido Liquidity Manager functionnalities
        * Invariant A: lidoWithdrawalQueueAmount == ∑lidoRequestRedeem.assets
        * Invariant B: address(arm).balance == 0
        * Invariant C: All slot allow for gap are empty
    
     * After invariants:
        * All user can withdraw their funds
        * Log stats
     
    
    */

    //////////////////////////////////////////////////////
    /// --- SWAP ASSERTIONS
    //////////////////////////////////////////////////////
    function assert_swap_invariant_A() public view {
        uint256 inflows = lpHandler.sum_of_deposits() + swapHandler.sum_of_weth_in()
            + llmHandler.sum_of_redeemed_ether() + donationHandler.sum_of_weth_donated() + MIN_TOTAL_SUPPLY;
        uint256 outflows = lpHandler.sum_of_withdraws() + swapHandler.sum_of_weth_out() + ownerHandler.sum_of_fees();
        assertEq(weth.balanceOf(address(lidoARM)), inflows - outflows, "swapHandler.invariant_A");
    }

    function assert_swap_invariant_B() public view {
        uint256 inflows = swapHandler.sum_of_steth_in() + donationHandler.sum_of_steth_donated();
        uint256 outflows = swapHandler.sum_of_steth_out() + llmHandler.sum_of_requested_ether();
        uint256 sum_of_errors = MockSTETH(address(steth)).sum_of_errors();
        assertApproxEqAbs(
            steth.balanceOf(address(lidoARM)), absDiff(inflows, outflows), sum_of_errors, "swapHandler.invariant_B"
        );
    }

    //////////////////////////////////////////////////////
    /// --- LIQUIDITY PROVIDER ASSERTIONS
    //////////////////////////////////////////////////////
    function assert_lp_invariant_A() public view {
        assertGt(lidoARM.totalSupply(), 0, "lpHandler.invariant_A");
    }

    function assert_lp_invariant_B() public view {
        uint256 sumOfUserShares;
        for (uint256 i; i < lps.length; i++) {
            address user = lps[i];
            sumOfUserShares += lidoARM.balanceOf(user);
        }
        assertEq(lidoARM.totalSupply(), _sumOfUserShares(), "lpHandler.invariant_B");
    }

    function assert_lp_invariant_C() public view {
        assertEq(lidoARM.previewRedeem(_sumOfUserShares()), lidoARM.totalAssets(), "lpHandler.invariant_C");
    }

    function assert_lp_invariant_D() public view {
        // Not really an invariant, but tested on handler
    }

    function assert_lp_invariant_E() public view {
        // Not really an invariant, but tested on handler
    }

    function assert_lp_invariant_F() public view {
        assertEq(
            lidoARM.nextWithdrawalIndex(), lpHandler.numberOfCalls("lpHandler.requestRedeem"), "lpHandler.invariant_F"
        );
    }

    function assert_lp_invariant_G() public view {
        assertEq(lidoARM.withdrawsQueued(), lpHandler.sum_of_requests(), "lpHandler.invariant_G");
    }

    function assert_lp_invariant_H() public view {
        assertGe(lidoARM.withdrawsQueued(), lidoARM.withdrawsClaimed(), "lpHandler.invariant_H");
    }

    function assert_lp_invariant_I() public view {
        uint256 sum;
        uint256 nextWithdrawalIndex = lidoARM.nextWithdrawalIndex();
        for (uint256 i; i < nextWithdrawalIndex; i++) {
            (,,, uint128 assets,) = lidoARM.withdrawalRequests(i);
            sum += assets;
        }

        assertEq(lidoARM.withdrawsQueued(), sum, "lpHandler.invariant_I");
    }

    function assert_lp_invariant_J() public view {
        assertEq(lidoARM.withdrawsClaimed(), lpHandler.sum_of_withdraws(), "lpHandler.invariant_J");
    }

    function assert_lp_invariant_K() public view {
        uint256 nextWithdrawalIndex = lidoARM.nextWithdrawalIndex();
        for (uint256 i; i < nextWithdrawalIndex; i++) {
            (,,, uint128 assets, uint128 queued) = lidoARM.withdrawalRequests(i);
            assertGe(queued, assets, "lpHandler.invariant_L");
        }
    }

    function assert_lp_invariant_L(uint256 initialBalance, uint256 maxError) public {
        // As  we will manipulate state here, we will snapshot the state and revert it after
        uint256 snapshotId = vm.snapshot();

        // 1. Finalize all claims on Lido
        llmHandler.finalizeAllClaims();

        // 2. Swap all stETH to WETH
        _sweepAllStETH();

        // 3. Finalize all claim redeem on ARM.
        lpHandler.finalizeAllClaims();

        for (uint256 i; i < lps.length; i++) {
            address user = lps[i];
            uint256 userShares = lidoARM.balanceOf(user);
            uint256 assets = lidoARM.previewRedeem(userShares);
            uint256 sum = assets + weth.balanceOf(user);

            if (sum < initialBalance) {
                // In this situation user have lost a bit of asset, ensure this is not too much
                assertApproxEqRel(sum, initialBalance, maxError, "lpHandler.invariant_L_a");
            } else {
                // In this case user have gained asset.
                assertGe(sum, initialBalance, "lpHandler.invariant_L_b");
            }
        }

        vm.revertToAndDelete(snapshotId);
    }

    function assert_lp_invariant_M() public view {
        address feeCollector = lidoARM.feeCollector();
        assertEq(weth.balanceOf(feeCollector), ownerHandler.sum_of_fees(), "lpHandler.invariant_M");
    }

    //////////////////////////////////////////////////////
    /// --- LIDO LIQUIDITY MANAGER ASSERTIONS
    //////////////////////////////////////////////////////
    function assert_llm_invariant_A() public view {
        assertEq(
            lidoARM.lidoWithdrawalQueueAmount(),
            llmHandler.sum_of_requested_ether() - llmHandler.sum_of_redeemed_ether(),
            "llmHandler.invariant_A"
        );
    }

    function assert_llm_invariant_B() public view {
        assertEq(address(lidoARM).balance, 0, "llmHandler.invariant_B");
    }

    function assert_llm_invariant_C() public view {
        uint256 slotGap1 = 1;
        uint256 slotGap2 = 59;
        uint256 gap1Length = 49;
        uint256 gap2Length = 41;

        for (uint256 i = slotGap1; i < slotGap1 + gap1Length; i++) {
            assertEq(readStorageSlotOnARM(i), 0, "lpHandler.invariant_C.gap1");
        }

        for (uint256 i = slotGap2; i < slotGap2 + gap2Length; i++) {
            assertEq(readStorageSlotOnARM(i), 0, "lpHandler.invariant_C.gap2");
        }
    }

    //////////////////////////////////////////////////////
    /// --- HELPERS
    //////////////////////////////////////////////////////
    /// @notice Sum of users shares, including dead shares
    function _sumOfUserShares() internal view returns (uint256) {
        uint256 sumOfUserShares;
        for (uint256 i; i < lps.length; i++) {
            address user = lps[i];
            sumOfUserShares += lidoARM.balanceOf(user);
        }
        return sumOfUserShares + lidoARM.balanceOf(address(0xdEaD));
    }

    /// @notice Swap all stETH to WETH at the current price
    function _sweepAllStETH() internal {
        uint256 stETHBalance = steth.balanceOf(address(lidoARM));
        deal(address(weth), address(this), 1_000_000_000 ether);
        weth.approve(address(lidoARM), type(uint256).max);
        lidoARM.swapTokensForExactTokens(weth, steth, stETHBalance, type(uint256).max, address(this));
        assertApproxEqAbs(steth.balanceOf(address(lidoARM)), 0, 1, "SwepAllStETH");
    }

    /// @notice Empties the ARM
    /// @dev Finalize all claims on lido, swap all stETH to WETH, finalize all
    /// claim redeem on ARM and withdraw all user funds.
    function emptiesARM() internal {
        // 1. Finalize all claims on Lido
        llmHandler.finalizeAllClaims();

        // 2. Swap all stETH to WETH
        _sweepAllStETH();

        // 3. Finalize all claim redeem on ARM.
        lpHandler.finalizeAllClaims();

        // 4. Withdraw all user funds
        lpHandler.withdrawAllUserFunds();
    }

    /// @notice Absolute difference between two numbers
    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function readStorageSlotOnARM(uint256 slotNumber) internal view returns (uint256 value) {
        value = uint256(vm.load(address(lidoARM), bytes32(slotNumber)));
    }

    function logStats() public view {
        // Don't trace this function as it's only for logging data.
        vm.pauseTracing();
        // Get data
        _LPHandler memory lpHandlerStats = _LPHandler({
            deposit: lpHandler.numberOfCalls("lpHandler.deposit"),
            deposit_skip: lpHandler.numberOfCalls("lpHandler.deposit.skip"),
            requestRedeem: lpHandler.numberOfCalls("lpHandler.requestRedeem"),
            requestRedeem_skip: lpHandler.numberOfCalls("lpHandler.requestRedeem.skip"),
            claimRedeem: lpHandler.numberOfCalls("lpHandler.claimRedeem"),
            claimRedeem_skip: lpHandler.numberOfCalls("lpHandler.claimRedeem.skip")
        });

        _SwapHandler memory swapHandlerStats = _SwapHandler({
            swapExact: swapHandler.numberOfCalls("swapHandler.swapExact"),
            swapExact_skip: swapHandler.numberOfCalls("swapHandler.swapExact.skip"),
            swapTokens: swapHandler.numberOfCalls("swapHandler.swapTokens"),
            swapTokens_skip: swapHandler.numberOfCalls("swapHandler.swapTokens.skip")
        });

        _OwnerHandler memory ownerHandlerStats = _OwnerHandler({
            setPrices: ownerHandler.numberOfCalls("ownerHandler.setPrices"),
            setPrices_skip: ownerHandler.numberOfCalls("ownerHandler.setPrices.skip"),
            setCrossPrice: ownerHandler.numberOfCalls("ownerHandler.setCrossPrice"),
            setCrossPrice_skip: ownerHandler.numberOfCalls("ownerHandler.setCrossPrice.skip"),
            collectFees: ownerHandler.numberOfCalls("ownerHandler.collectFees"),
            collectFees_skip: ownerHandler.numberOfCalls("ownerHandler.collectFees.skip"),
            setFees: ownerHandler.numberOfCalls("ownerHandler.setFees"),
            setFees_skip: ownerHandler.numberOfCalls("ownerHandler.setFees.skip")
        });

        _LLMHandler memory llmHandlerStats = _LLMHandler({
            requestStETHWithdraw: llmHandler.numberOfCalls("llmHandler.requestStETHWithdraw"),
            claimStETHWithdraw: llmHandler.numberOfCalls("llmHandler.claimStETHWithdraw")
        });

        _DonationHandler memory donationHandlerStats = _DonationHandler({
            donateStETH: donationHandler.numberOfCalls("donationHandler.donateStETH"),
            donateWETH: donationHandler.numberOfCalls("donationHandler.donateWETH")
        });

        // Log data
        console.log("");
        console.log("");
        console.log("");
        console.log("--- Stats ---");

        // --- LP Handler ---
        console.log("");
        console.log("# LP Handler # ");
        console.log("Number of Call: Deposit %d (skipped: %d)", lpHandlerStats.deposit, lpHandlerStats.deposit_skip);
        console.log(
            "Number of Call: RequestRedeem %d (skipped: %d)",
            lpHandlerStats.requestRedeem,
            lpHandlerStats.requestRedeem_skip
        );
        console.log(
            "Number of Call: ClaimRedeem %d (skipped: %d)", lpHandlerStats.claimRedeem, lpHandlerStats.claimRedeem_skip
        );

        // --- Swap Handler ---
        console.log("");
        console.log("# Swap Handler #");
        console.log(
            "Number of Call: SwapExactTokensForTokens %d (skipped: %d)",
            swapHandlerStats.swapExact,
            swapHandlerStats.swapExact_skip
        );
        console.log(
            "Number of Call: SwapTokensForExactTokens %d (skipped: %d)",
            swapHandlerStats.swapTokens,
            swapHandlerStats.swapTokens_skip
        );

        // --- Owner Handler ---
        console.log("");
        console.log("# Owner Handler #");
        console.log(
            "Number of Call: SetPrices %d (skipped: %d)", ownerHandlerStats.setPrices, ownerHandlerStats.setPrices_skip
        );
        console.log(
            "Number of Call: SetCrossPrice %d (skipped: %d)",
            ownerHandlerStats.setCrossPrice,
            ownerHandlerStats.setCrossPrice_skip
        );
        console.log(
            "Number of Call: CollectFees %d (skipped: %d)",
            ownerHandlerStats.collectFees,
            ownerHandlerStats.collectFees_skip
        );
        console.log(
            "Number of Call: SetFees %d (skipped: %d)", ownerHandlerStats.setFees, ownerHandlerStats.setFees_skip
        );

        // --- LLM Handler ---
        console.log("");
        console.log("# LLM Handler #");
        console.log(
            "Number of Call: RequestStETHWithdrawalForETH %d (skipped: %d)", llmHandlerStats.requestStETHWithdraw, 0
        );
        console.log(
            "Number of Call: ClaimStETHWithdrawalForWETH %d (skipped: %d)", llmHandlerStats.claimStETHWithdraw, 0
        );

        // --- Donation Handler ---
        console.log("");
        console.log("# Donation Handler #");
        console.log("Number of Call: DonateStETH %d (skipped: %d)", donationHandlerStats.donateStETH, 0);
        console.log("Number of Call: DonateWETH %d (skipped: %d)", donationHandlerStats.donateWETH, 0);

        // --- Global ---
        console.log("");
        console.log("# Global Data #");
        uint256 sumOfCall = donationHandlerStats.donateStETH + donationHandlerStats.donateWETH
            + llmHandlerStats.requestStETHWithdraw + llmHandlerStats.claimStETHWithdraw + ownerHandlerStats.setPrices
            + ownerHandlerStats.setCrossPrice + ownerHandlerStats.collectFees + ownerHandlerStats.setFees
            + swapHandlerStats.swapExact + swapHandlerStats.swapTokens + lpHandlerStats.deposit
            + lpHandlerStats.requestRedeem + lpHandlerStats.claimRedeem;
        uint256 sumOfCall_skip = ownerHandlerStats.setPrices_skip + ownerHandlerStats.setCrossPrice_skip
            + ownerHandlerStats.collectFees_skip + ownerHandlerStats.setFees_skip + swapHandlerStats.swapExact_skip
            + swapHandlerStats.swapTokens_skip + lpHandlerStats.deposit_skip + lpHandlerStats.requestRedeem_skip
            + lpHandlerStats.claimRedeem_skip;

        uint256 skipPct = (sumOfCall_skip * 10_000) / max(sumOfCall, 1);
        console.log("Total call: %d (skipped: %d) -> %2e%", sumOfCall, sumOfCall_skip, skipPct);
        console.log("");
        console.log("-------------");
        console.log("");
        console.log("");
        console.log("");
        vm.resumeTracing();
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    struct _LPHandler {
        uint256 deposit;
        uint256 deposit_skip;
        uint256 requestRedeem;
        uint256 requestRedeem_skip;
        uint256 claimRedeem;
        uint256 claimRedeem_skip;
    }

    struct _SwapHandler {
        uint256 swapExact;
        uint256 swapExact_skip;
        uint256 swapTokens;
        uint256 swapTokens_skip;
    }

    struct _OwnerHandler {
        uint256 setPrices;
        uint256 setPrices_skip;
        uint256 setCrossPrice;
        uint256 setCrossPrice_skip;
        uint256 collectFees;
        uint256 collectFees_skip;
        uint256 setFees;
        uint256 setFees_skip;
    }

    struct _LLMHandler {
        uint256 requestStETHWithdraw;
        uint256 claimStETHWithdraw;
    }

    struct _DonationHandler {
        uint256 donateStETH;
        uint256 donateWETH;
    }
}
