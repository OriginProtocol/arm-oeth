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
    /// --- INVARIANTS
    //////////////////////////////////////////////////////
    /*
     * Swap functionnalities (swap)
        * Invariant A: weth balance >= ∑deposit + ∑wethIn - ∑withdraw - ∑wethOut - ∑feesCollected
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


    /// @notice Sum of users shares, including dead shares
    function _sumOfUserShares() internal view returns (uint256) {
        uint256 sumOfUserShares;
        for (uint256 i; i < lps.length; i++) {
            address user = lps[i];
            sumOfUserShares += lidoARM.balanceOf(user);
        }
        return sumOfUserShares + lidoARM.balanceOf(address(0xdEaD));
    }
}
