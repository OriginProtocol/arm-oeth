// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_MultiAssetARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";
import {Ownable} from "contracts/Ownable.sol";
import {OwnableOperable} from "contracts/OwnableOperable.sol";

/// @notice Coverage for `pause()` (operator or owner) and `unpause()` (owner only).
///         The downstream `whenNotPaused` reverts on user-facing functions are
///         already covered in the per-function test files (Deposit, ClaimRedeem,
///         RequestRedeem, Swap*). Here we focus on the access control, the
///         `paused` state flip, and the events.
contract Unit_MultiAssetARM_Pause_Test is Unit_MultiAssetARM_Shared_Test {
    //////////////////////////////////////////////////////
    /// --- pause
    //////////////////////////////////////////////////////
    function test_Pause_ByOwner() public {
        assertEq(arm.paused(), false, "paused pre");

        vm.expectEmit(address(arm));
        emit AbstractARM.Paused(governor);

        vm.prank(governor);
        arm.pause();

        assertEq(arm.paused(), true, "paused post");
    }

    function test_Pause_ByOperator() public {
        assertEq(arm.paused(), false, "paused pre");

        vm.expectEmit(address(arm));
        emit AbstractARM.Paused(operator);

        vm.prank(operator);
        arm.pause();

        assertEq(arm.paused(), true, "paused post");
    }

    function test_Pause_RevertWhen_NotAuthorized() public {
        vm.prank(alice);
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        arm.pause();
    }

    //////////////////////////////////////////////////////
    /// --- unpause
    //////////////////////////////////////////////////////
    function test_Unpause_ByOwner() public {
        vm.prank(governor);
        arm.pause();
        assertEq(arm.paused(), true, "paused pre");

        vm.expectEmit(address(arm));
        emit AbstractARM.Unpaused(governor);

        vm.prank(governor);
        arm.unpause();

        assertEq(arm.paused(), false, "paused post");
    }

    function test_Unpause_RevertWhen_Operator() public {
        // The operator can pause but cannot unpause — that's reserved for the owner.
        vm.prank(operator);
        arm.pause();

        vm.prank(operator);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        arm.unpause();
    }

    function test_Unpause_RevertWhen_NotAuthorized() public {
        vm.prank(governor);
        arm.pause();

        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        arm.unpause();
    }

    /// @notice Pausing an already-paused ARM is a no-op state-wise but still emits the event.
    function test_Pause_WhenAlreadyPaused() public {
        vm.prank(governor);
        arm.pause();
        assertEq(arm.paused(), true, "paused pre");

        vm.expectEmit(address(arm));
        emit AbstractARM.Paused(operator);

        vm.prank(operator);
        arm.pause();

        assertEq(arm.paused(), true, "still paused");
    }

    //////////////////////////////////////////////////////
    /// --- whenNotPaused gating: deposit / requestRedeem / claimRedeem
    //////////////////////////////////////////////////////
    function test_RevertWhen_Deposit_Because_Paused() public {
        vm.prank(operator);
        arm.pause();

        vm.expectRevert(AbstractARM.ContractPaused.selector);
        vm.prank(alice);
        arm.deposit(DEFAULT_AMOUNT());
    }

    function test_RevertWhen_DepositWithReceiver_Because_Paused() public {
        vm.prank(operator);
        arm.pause();

        vm.expectRevert(AbstractARM.ContractPaused.selector);
        vm.prank(alice);
        arm.deposit(DEFAULT_AMOUNT(), bobby);
    }

    function test_RevertWhen_RequestRedeem_Because_Paused() public {
        // First deposit so alice has shares to redeem.
        vm.prank(alice);
        arm.deposit(DEFAULT_AMOUNT());

        vm.prank(operator);
        arm.pause();

        vm.expectRevert(AbstractARM.ContractPaused.selector);
        vm.prank(alice);
        arm.requestRedeem(DEFAULT_AMOUNT());
    }

    function test_RevertWhen_ClaimRedeem_Because_Paused() public {
        // Alice deposits then requests a full redeem.
        vm.startPrank(alice);
        uint256 shares = arm.deposit(DEFAULT_AMOUNT());
        arm.requestRedeem(shares);
        vm.stopPrank();

        vm.prank(operator);
        arm.pause();

        // Wait for the claim delay so only the pause gate can block the claim.
        vm.warp(block.timestamp + CLAIM_DELAY);

        uint256 balanceBefore = liquidity.balanceOf(alice);
        vm.expectRevert(AbstractARM.ContractPaused.selector);
        vm.prank(alice);
        arm.claimRedeem(0);
        assertEq(liquidity.balanceOf(alice), balanceBefore, "alice should not claim while paused");
    }

    /// @notice After unpause, deposit and requestRedeem work again.
    function test_DepositAndRedeem_After_Unpause() public {
        vm.prank(operator);
        arm.pause();
        vm.prank(governor);
        arm.unpause();

        vm.prank(alice);
        uint256 shares = arm.deposit(DEFAULT_AMOUNT());
        assertGt(shares, 0, "alice should have received shares");

        vm.prank(alice);
        (uint256 requestId,) = arm.requestRedeem(shares);
        assertEq(requestId, 0, "first request");
    }

    /// @dev Give alice liquidity for the deposit/redeem gating tests. Approvals are set by the shared harness.
    ///      Caps are disabled so deposits are only gated by the pause state under test.
    function setUp() public virtual override {
        super.setUp();
        desactiveCapManager();
        deal(address(liquidity), alice, 1_000 * DEFAULT_AMOUNT());
    }
}
