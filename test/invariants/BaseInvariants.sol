// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Invariant_Shared_Test_} from "./shared/Shared.sol";

// Handlers
import {LpHandler} from "./handlers/LpHandler.sol";
import {LLMHandler} from "./handlers/LLMHandler.sol";
import {SwapHandler} from "./handlers/SwapHandler.sol";
import {OwnerHandler} from "./handlers/OwnerHandler.sol";

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
        * Invariant A: weth balance >= ∑deposit + ∑wethIn + ∑wethRedeem - ∑withdraw - ∑wethOut - ∑feesCollected
        * Invariant A: steth balance >= ∑stethIn - ∑stethOut - ∑stethRedeem
    
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
            * Invariant H: withdrawsQueued > withdrawsClaimable
            * Invariant I: withdrawsClaimable > withdrawsClaimed
            * Invariant J: withdrawsClaimed == ∑claimRedeem.amount

        * Total Assets:
            * Invariant K: totalAssets >= ∑deposit - ∑withdraw
            * Invariant L :totalAssets >= lastAvailableAssets

        * Fees:
            * Invariant M: ∑feesCollected == feeCollector.balance

     * Lido Liquidity Manager functionnalities
        * Invariant A: outstandingEther == ∑lidoRequestRedeem.assets
        * Invariant B: address(arm).balance == 0
    
    */

    //////////////////////////////////////////////////////
    /// --- SWAP ASSERTIONS
    //////////////////////////////////////////////////////
    function assert_swap_invariant_A() public view {
        uint256 inflows = lpHandler.sum_of_deposits() + swapHandler.sum_of_weth_in()
            + llmHandler.sum_of_redeemed_ether() + MIN_TOTAL_SUPPLY;
        uint256 outflows = lpHandler.sum_of_withdraws() + swapHandler.sum_of_weth_out() + ownerHandler.sum_of_fees();
        assertEq(weth.balanceOf(address(lidoARM)), inflows - outflows, "swapHandler.invariant_A");
    }

    function assert_swap_invariant_B() public view {
        uint256 inflows = swapHandler.sum_of_steth_in();
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
        assertGe(lidoARM.withdrawsQueued(), lidoARM.withdrawsClaimable(), "lpHandler.invariant_H");
    }

    function assert_lp_invariant_I() public view {
        assertGe(lidoARM.withdrawsClaimable(), lidoARM.withdrawsClaimed(), "lpHandler.invariant_I");
    }

    function assert_lp_invariant_J() public view {
        assertEq(lidoARM.withdrawsClaimed(), lpHandler.sum_of_withdraws(), "lpHandler.invariant_J");
    }

    function assert_lp_invariant_M() public view {
        address feeCollector = lidoARM.feeCollector();
        assertEq(weth.balanceOf(feeCollector), ownerHandler.sum_of_fees(), "lpHandler.invariant_M");
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
}
