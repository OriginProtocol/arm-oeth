// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {console} from "forge-std/Console.sol";

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
            (,,, uint120 assets,) = lidoARM.withdrawalRequests(i);
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
            (,,, uint120 assets, uint120 queued) = lidoARM.withdrawalRequests(i);
            assertGe(queued, assets, "lpHandler.invariant_L");
        }
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
        uint256 slotGap2 = 58;
        uint256 gap1Length = 49;
        uint256 gap2Length = 43;

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

    /// @notice Absolute difference between two numbers
    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function readStorageSlotOnARM(uint256 slotNumber) internal view returns (uint256 value) {
        value = uint256(vm.load(address(lidoARM), bytes32(slotNumber)));
    }

    function logsStats() public view {
        console.log("");
        console.log("--- Stats ---");

        console.log("");
        console.log("# LP Handler #");
        console.log(
            "Number of Call: Deposit %d (skipped: %d)",
            lpHandler.numberOfCalls("lpHandler.deposit"),
            lpHandler.numberOfCalls("lpHandler.deposit.skip")
        );
        console.log(
            "Number of Call: RequestRedeem %d (skipped: %d)",
            lpHandler.numberOfCalls("lpHandler.requestRedeem"),
            lpHandler.numberOfCalls("lpHandler.requestRedeem.skip")
        );

        console.log(
            "Number of Call: ClaimRedeem %d (skipped: %d)",
            lpHandler.numberOfCalls("lpHandler.claimRedeem"),
            lpHandler.numberOfCalls("lpHandler.claimRedeem.skip")
        );

        console.log("");
        console.log("# Swap Handler #");
        console.log(
            "Number of Call: SwapExactTokensForTokens %d (skipped: %d)",
            swapHandler.numberOfCalls("swapHandler.swapExactTokens"),
            swapHandler.numberOfCalls("swapHandler.swapExactTokens.skip")
        );
        console.log(
            "Number of Call: SwapTokensForExactTokens %d (skipped: %d)",
            swapHandler.numberOfCalls("swapHandler.swapTokensExact"),
            swapHandler.numberOfCalls("swapHandler.swapTokensExact.skip")
        );

        console.log("");
        console.log("# Owner Handler #");
        console.log(
            "Number of Call: SetPrices %d (skipped: %d)",
            ownerHandler.numberOfCalls("ownerHandler.setPrices"),
            ownerHandler.numberOfCalls("ownerHandler.setPrices.skip")
        );
        console.log(
            "Number of Call: SetCrossPrice %d (skipped: %d)",
            ownerHandler.numberOfCalls("ownerHandler.setCrossPrice"),
            ownerHandler.numberOfCalls("ownerHandler.setCrossPrice.skip")
        );
        console.log(
            "Number of Call: CollectFees %d (skipped: %d)",
            ownerHandler.numberOfCalls("ownerHandler.collectFees"),
            ownerHandler.numberOfCalls("ownerHandler.collectFees.skip")
        );
        console.log(
            "Number of Call: SetFees %d (skipped: %d)",
            ownerHandler.numberOfCalls("ownerHandler.setFees"),
            ownerHandler.numberOfCalls("ownerHandler.setFees.skip")
        );

        console.log("");
        console.log("# LLM Handler #");
        console.log(
            "Number of Call: RequestStETHWithdrawalForETH %d (skipped: %d)",
            llmHandler.numberOfCalls("llmHandler.requestStETHWithdraw"),
            0
        );
        console.log(
            "Number of Call: ClaimStETHWithdrawalForWETH %d (skipped: %d)",
            llmHandler.numberOfCalls("llmHandler.claimStETHWithdraw"),
            0
        );

        console.log("");
        console.log("# Donation Handler #");
        console.log(
            "Number of Call: DonateStETH %d (skipped: %d)",
            donationHandler.numberOfCalls("donationHandler.donateStETH"),
            donationHandler.numberOfCalls("donationHandler.donateStETH.skip")
        );
        console.log(
            "Number of Call: DonateWETH %d (skipped: %d)",
            donationHandler.numberOfCalls("donationHandler.donateWETH"),
            donationHandler.numberOfCalls("donationHandler.donateWETH.skip")
        );
    }
}
